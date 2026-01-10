#!/bin/bash
# Ralph Loop PreToolUse Hook - Auto-approves safe commands for autonomous execution
#
# SECURITY NOTE: This hook is intentionally restrictive. It validates commands
# against strict patterns and rejects anything with shell metacharacters.

set -euo pipefail

readonly RALPH_STATE_FILE=".claude/ralph-loop.local.md"

# Output functions
approve() { echo '{"decision": "approve"}'; exit 0; }
deny() { printf '{"decision": "block", "reason": "%s"}\n' "$1"; exit 0; }
pass() { echo '{}'; exit 0; }

# Read and parse input
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[[ -z "$TOOL_NAME" ]] && pass
[[ ! -f "$RALPH_STATE_FILE" ]] && pass

# Validate Bash commands with strict pattern matching
validate_bash_command() {
    local cmd="$1"

    # Strip leading/trailing whitespace
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Reject shell metacharacters that enable command chaining or injection
    if echo "$cmd" | grep -qE '[;&|`$()]|^\s|\\'; then
        deny "Command contains unsafe shell metacharacters"
    fi

    # Validate against allowlist of safe command prefixes
    # Each pattern ensures the command starts with the tool name followed by space
    case "$cmd" in
        git\ [a-z][-a-z]*) approve ;;  # git subcommands only
        pnpm\ *|npm\ *|yarn\ *) approve ;;
        node\ [^-]*|npx\ *) approve ;;  # node without -e flag
        tsc\ *|eslint\ *|prettier\ *) approve ;;
        vitest\ *|jest\ *) approve ;;
        cargo\ *|make\ *) approve ;;
        python\ [^-c]*|pip\ *|poetry\ *|uv\ *) approve ;;  # python without -c
        *setup-ralph-loop.sh*) approve ;;
        rm\ -rf\ *|sudo\ *|curl\ *|wget\ *|eval\ *|exec\ *)
            deny "Command blocked by ralph-loop safety rules"
            ;;
        *) pass ;;
    esac
}

case "$TOOL_NAME" in
    Read|Write|Edit|MultiEdit) approve ;;
    Glob|Grep|LS|Task|TodoWrite) approve ;;
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        [[ -z "$COMMAND" ]] && pass
        validate_bash_command "$COMMAND"
        ;;
    *) pass ;;
esac
