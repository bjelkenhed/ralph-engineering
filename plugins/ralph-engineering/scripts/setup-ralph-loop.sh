#!/bin/bash

# Ralph Loop Setup Script
# Creates state file for in-session Ralph loop

set -euo pipefail

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=0
COMPLETION_PROMISE="null"
PRD_FILE="auto"  # auto, explicit path, or NONE

# Parse options and positional arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Loop - Interactive self-referential development loop

USAGE:
  /ralph-loop [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: unlimited)
  --completion-promise '<text>'  Promise phrase (USE QUOTES for multi-word)
  --prd <file|NONE>              PRD file path (default: auto-detect ./plans/prd.json)
  -h, --help                     Show this help message

DESCRIPTION:
  Starts a Ralph Wiggum loop in your CURRENT session. The stop hook prevents
  exit and feeds your output back as input until completion or iteration limit.

  To signal completion, you must output: <promise>YOUR_PHRASE</promise>

  Use this for:
  - Interactive iteration where you want to see progress
  - Tasks requiring self-correction and refinement
  - Learning how Ralph works

EXAMPLES:
  /ralph-loop Build a todo API --completion-promise 'DONE' --max-iterations 20
  /ralph-loop --max-iterations 10 Fix the auth bug
  /ralph-loop Refactor cache layer  (runs forever)
  /ralph-loop --completion-promise 'TASK COMPLETE' Create a REST API
  /ralph-loop --prd ./plans/prd.json  (use PRD with default prompt)
  /ralph-loop --prd NONE Build API  (disable PRD auto-detection)

STOPPING:
  Only by reaching --max-iterations or detecting --completion-promise
  No manual stop - Ralph runs infinitely by default!

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/ralph-loop.local.md

  # View full state:
  head -10 .claude/ralph-loop.local.md

  # View progress log:
  cat .claude/ralph-progress.txt
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --max-iterations requires a number argument" >&2
        echo "" >&2
        echo "   Valid examples:" >&2
        echo "     --max-iterations 10" >&2
        echo "     --max-iterations 50" >&2
        echo "     --max-iterations 0  (unlimited)" >&2
        echo "" >&2
        echo "   You provided: --max-iterations (with no number)" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: --max-iterations must be a positive integer or 0, got: $2" >&2
        echo "" >&2
        echo "   Valid examples:" >&2
        echo "     --max-iterations 10" >&2
        echo "     --max-iterations 50" >&2
        echo "     --max-iterations 0  (unlimited)" >&2
        echo "" >&2
        echo "   Invalid: decimals (10.5), negative numbers (-5), text" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --completion-promise requires a text argument" >&2
        echo "" >&2
        echo "   Valid examples:" >&2
        echo "     --completion-promise 'DONE'" >&2
        echo "     --completion-promise 'TASK COMPLETE'" >&2
        echo "     --completion-promise 'All tests passing'" >&2
        echo "" >&2
        echo "   You provided: --completion-promise (with no text)" >&2
        echo "" >&2
        echo "   Note: Multi-word promises must be quoted!" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --prd)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --prd requires a file path or 'NONE'" >&2
        echo "" >&2
        echo "   Valid examples:" >&2
        echo "     --prd ./plans/prd.json" >&2
        echo "     --prd /absolute/path/to/prd.json" >&2
        echo "     --prd NONE  (disable auto-detection)" >&2
        echo "" >&2
        echo "   Default: auto-detect ./plans/prd.json" >&2
        exit 1
      fi
      PRD_FILE="$2"
      shift 2
      ;;
    *)
      # Non-option argument - collect all as prompt parts
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# Join all prompt parts with spaces (handle empty array with set -u)
PROMPT="${PROMPT_PARTS[*]:-}"

# Handle PRD auto-detection
RESOLVED_PRD_FILE=""
if [[ "$PRD_FILE" == "auto" ]]; then
  if [[ -f "./plans/prd.json" ]]; then
    RESOLVED_PRD_FILE="./plans/prd.json"
  fi
elif [[ "$PRD_FILE" != "NONE" ]] && [[ -n "$PRD_FILE" ]]; then
  if [[ -f "$PRD_FILE" ]]; then
    RESOLVED_PRD_FILE="$PRD_FILE"
  else
    echo "❌ Error: PRD file not found: $PRD_FILE" >&2
    exit 1
  fi
fi

# If PRD exists and no prompt provided, use default prompt and completion promise
if [[ -n "$RESOLVED_PRD_FILE" ]] && [[ -z "$PROMPT" ]]; then
  PROMPT="Implement features from the PRD file at $RESOLVED_PRD_FILE"
  if [[ "$COMPLETION_PROMISE" == "null" ]]; then
    COMPLETION_PROMISE="COMPLETE"
  fi
fi

# Validate prompt is non-empty
if [[ -z "$PROMPT" ]]; then
  echo "❌ Error: No prompt provided" >&2
  echo "" >&2
  echo "   Ralph needs a task description to work on." >&2
  echo "" >&2
  echo "   Examples:" >&2
  echo "     /ralph-loop Build a REST API for todos" >&2
  echo "     /ralph-loop Fix the auth bug --max-iterations 20" >&2
  echo "     /ralph-loop --completion-promise 'DONE' Refactor code" >&2
  echo "     /ralph-loop  (auto-uses ./plans/prd.json if it exists)" >&2
  echo "" >&2
  echo "   For all options: /ralph-loop --help" >&2
  exit 1
fi

# Create state file for stop hook (markdown with YAML frontmatter)
mkdir -p .claude

# Helper function to escape strings for YAML
yaml_escape_string() {
  local value="$1"
  if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
    echo "null"
    return
  fi
  # Escape backslashes first, then double quotes
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

# Quote completion promise for YAML with proper escaping
COMPLETION_PROMISE_YAML=$(yaml_escape_string "$COMPLETION_PROMISE")

# Quote PRD file for YAML with proper escaping
PRD_FILE_YAML=$(yaml_escape_string "$RESOLVED_PRD_FILE")

cat > .claude/ralph-loop.local.md <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: $COMPLETION_PROMISE_YAML
prd_file: $PRD_FILE_YAML
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

# Initialize empty progress file for tracking accomplishments across iterations
touch .claude/ralph-progress.txt

# Get PRD status if available
PRD_STATUS_MSG=""
if [[ -n "$RESOLVED_PRD_FILE" ]]; then
  if command -v jq &> /dev/null; then
    TOTAL=$(jq '.features | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "?")
    PASSING=$(jq '[.features[] | select(.passes == true)] | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
    PRD_STATUS_MSG="PRD: $RESOLVED_PRD_FILE ($PASSING/$TOTAL features passing)"
  else
    PRD_STATUS_MSG="PRD: $RESOLVED_PRD_FILE (jq not installed - cannot count features)"
  fi
fi

# Output setup message
cat <<EOF
🔄 Ralph loop activated in this session!

Iteration: 1
Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)
Completion promise: $(if [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "${COMPLETION_PROMISE//\"/} (ONLY output when TRUE - do not lie!)"; else echo "none (runs forever)"; fi)
$(if [[ -n "$PRD_STATUS_MSG" ]]; then echo "$PRD_STATUS_MSG"; fi)

The stop hook is now active. When you try to exit, the SAME PROMPT will be
fed back to you. You'll see your previous work in files, creating a
self-referential loop where you iteratively improve on the same task.

To monitor: head -10 .claude/ralph-loop.local.md
To view progress: cat .claude/ralph-progress.txt

⚠️  WARNING: This loop cannot be stopped manually! It will run infinitely
    unless you set --max-iterations or --completion-promise.

🔄
EOF

# Output the initial prompt if provided
if [[ -n "$PROMPT" ]]; then
  echo ""
  echo "$PROMPT"
fi

# Display completion promise requirements if set
if [[ "$COMPLETION_PROMISE" != "null" ]]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "CRITICAL - Ralph Loop Completion Promise"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "To complete this loop, output this EXACT text:"
  echo "  <promise>$COMPLETION_PROMISE</promise>"
  echo ""
  echo "STRICT REQUIREMENTS (DO NOT VIOLATE):"
  echo "  ✓ Use <promise> XML tags EXACTLY as shown above"
  echo "  ✓ The statement MUST be completely and unequivocally TRUE"
  echo "  ✓ Do NOT output false statements to exit the loop"
  echo "  ✓ Do NOT lie even if you think you should exit"
  echo ""
  echo "IMPORTANT - Do not circumvent the loop:"
  echo "  Even if you believe you're stuck, the task is impossible,"
  echo "  or you've been running too long - you MUST NOT output a"
  echo "  false promise statement. The loop is designed to continue"
  echo "  until the promise is GENUINELY TRUE. Trust the process."
  echo ""
  echo "  If the loop should stop, the promise statement will become"
  echo "  true naturally. Do not force it by lying."
  echo "═══════════════════════════════════════════════════════════"
fi