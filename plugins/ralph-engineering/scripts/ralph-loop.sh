#!/bin/bash

# Ralph Loop - External orchestrator with fresh context per iteration
# Each iteration runs as a separate `claude -p` session with no context carryover.
# State is passed via files (progress.txt, PRD, git history).

set -euo pipefail

# Store original arguments for background spawning
ORIGINAL_ARGS=("$@")

# Get script directory to find templates
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/../templates/ralph-loop-prompt.md"
ARCHITECTURE_FILE="$SCRIPT_DIR/../templates/architecture.md"

# State files
STATE_FILE=".claude/ralph-loop-state.json"
PROGRESS_FILE=".claude/ralph-progress.txt"

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=20
MAX_ITERATIONS_EXPLICIT=false
COMPLETION_PROMISE="COMPLETE"
PRD_FILE="auto"
VERBOSE=false
FOREGROUND=false

# Parse options and positional arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Loop - Fresh context per iteration development loop

USAGE:
  /ralph-loop [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: 20,
                                 or PRD feature count if greater)
  --completion-promise '<text>'  Promise phrase (default: COMPLETE)
  --prd <file|NONE>              PRD file path (default: auto-detect ./plans/prd.json)
  --verbose                      Show detailed output from each iteration
  --foreground                   Run in foreground (blocking mode, subject to timeout)
  -h, --help                     Show this help message

DESCRIPTION:
  Runs Claude in an external loop where each iteration gets FRESH context.
  This follows Anthropic's recommended pattern for long-running agents.

  By default, runs in BACKGROUND mode to avoid timeout limits. The command
  returns immediately with monitoring instructions. Use --foreground for
  blocking mode (subject to 10-minute timeout).

  Each iteration:
  1. Starts a new Claude session (claude -p)
  2. Reads progress from .claude/ralph-progress.txt
  3. Checks git history for recent commits
  4. Works on ONE feature from the PRD
  5. Commits changes and updates progress

  To signal completion, output: <promise>YOUR_PHRASE</promise>

EXAMPLES:
  /ralph-loop --prd ./plans/prd.json  (use PRD with default settings)
  /ralph-loop Build a todo API --max-iterations 10
  /ralph-loop --verbose --prd ./plans/prd.json

DIFFERENCES FROM /ralph-session:
  - /ralph-loop: Fresh context each iteration (external orchestrator)
  - /ralph-session: Same context, stop hook prevents exit

MONITORING:
  # View state:
  cat .claude/ralph-loop-state.json

  # View progress log:
  cat .claude/ralph-progress.txt

  # Stop the loop:
  Press Ctrl+C
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations requires a positive integer" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      MAX_ITERATIONS_EXPLICIT=true
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --prd)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --prd requires a file path or 'NONE'" >&2
        exit 1
      fi
      PRD_FILE="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --foreground)
      FOREGROUND=true
      shift
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

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
    echo "Error: PRD file not found: $PRD_FILE" >&2
    exit 1
  fi
fi

# If PRD exists and no prompt provided, use default prompt
if [[ -n "$RESOLVED_PRD_FILE" ]] && [[ -z "$PROMPT" ]]; then
  PROMPT="Implement features from the PRD file at $RESOLVED_PRD_FILE"
fi

# Validate prompt is non-empty
if [[ -z "$PROMPT" ]]; then
  echo "Error: No prompt provided" >&2
  echo "Usage: /ralph-loop [PROMPT] [OPTIONS]" >&2
  echo "For help: /ralph-loop --help" >&2
  exit 1
fi

# If max-iterations not explicitly set and PRD exists, use feature count
if [[ "$MAX_ITERATIONS_EXPLICIT" == "false" ]] && [[ -n "$RESOLVED_PRD_FILE" ]]; then
  if command -v jq &> /dev/null; then
    PRD_FEATURE_COUNT=$(jq '.features | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
    if [[ "$PRD_FEATURE_COUNT" =~ ^[0-9]+$ ]] && [[ "$PRD_FEATURE_COUNT" -gt "$MAX_ITERATIONS" ]]; then
      MAX_ITERATIONS="$PRD_FEATURE_COUNT"
    fi
  fi
fi

# Settings template for permissions
SETTINGS_TEMPLATE="$SCRIPT_DIR/../templates/settings.ralph-loop.json"

# Function to merge ralph-loop permissions into settings.local.json
merge_permissions() {
  local settings_file=".claude/settings.local.json"
  local temp_file

  # Check if template exists
  if [[ ! -f "$SETTINGS_TEMPLATE" ]]; then
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Permissions template not found: $SETTINGS_TEMPLATE" >&2
    return 0
  fi

  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    [[ "$VERBOSE" == "true" ]] && echo "Warning: jq not installed - cannot merge permissions" >&2
    return 0
  fi

  # Validate template has expected structure
  if ! jq -e '.permissions.allow' "$SETTINGS_TEMPLATE" &>/dev/null; then
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Template missing .permissions.allow" >&2
    return 0
  fi

  # Create .claude directory if needed
  mkdir -p .claude

  # Create empty settings if file doesn't exist or is invalid
  if [[ ! -f "$settings_file" ]] || ! jq -e '.permissions.allow' "$settings_file" &>/dev/null; then
    echo '{"permissions":{"allow":[]}}' > "$settings_file"
  fi

  # Create temp file for atomic write
  temp_file="$(mktemp)" || {
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Failed to create temp file" >&2
    return 0
  }

  # Merge permissions arrays and defaultMode
  if ! jq -s '
    .[0].permissions.allow as $existing |
    .[1].permissions.allow as $template |
    .[1].permissions.defaultMode as $mode |
    .[0] | .permissions.allow = ($existing + $template | unique) | .permissions.defaultMode = $mode
  ' "$settings_file" "$SETTINGS_TEMPLATE" > "$temp_file" 2>&1; then
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Failed to merge permissions" >&2
    rm -f "$temp_file"
    return 0
  fi

  # Validate output is valid JSON
  if ! jq -e '.permissions.allow' "$temp_file" &>/dev/null; then
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Merge produced invalid output" >&2
    rm -f "$temp_file"
    return 0
  fi

  # Atomic move
  mv "$temp_file" "$settings_file" || {
    [[ "$VERBOSE" == "true" ]] && echo "Warning: Failed to write $settings_file" >&2
    rm -f "$temp_file"
    return 0
  }

  [[ "$VERBOSE" == "true" ]] && echo "Auto-approved permissions for ralph-loop"
}

# Merge permissions before starting
merge_permissions

# Create state directory
mkdir -p .claude

# Initialize state file
init_state() {
  local prd_total=0
  local prd_passing=0

  if [[ -n "$RESOLVED_PRD_FILE" ]] && command -v jq &> /dev/null; then
    prd_total=$(jq '.features | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
    prd_passing=$(jq '[.features[] | select(.passes == true)] | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
  fi

  jq -n \
    --arg prompt "$PROMPT" \
    --arg prd_file "$RESOLVED_PRD_FILE" \
    --arg completion_promise "$COMPLETION_PROMISE" \
    --argjson max_iterations "$MAX_ITERATIONS" \
    --argjson prd_total "$prd_total" \
    --argjson prd_passing "$prd_passing" \
    '{
      iteration: 1,
      max_iterations: $max_iterations,
      prompt: $prompt,
      prd_file: $prd_file,
      completion_promise: $completion_promise,
      prd_total: $prd_total,
      prd_passing: $prd_passing,
      started_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      status: "running"
    }' > "$STATE_FILE"
}

# Update state iteration
update_state_iteration() {
  local iteration=$1
  local prd_passing=$2

  jq --argjson iter "$iteration" --argjson passing "$prd_passing" \
    '.iteration = $iter | .prd_passing = $passing | .last_updated = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Mark state complete
mark_state_complete() {
  jq '.status = "complete" | .completed_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Build the iteration prompt
build_iteration_prompt() {
  local iteration=$1
  local prd_total=$2
  local prd_passing=$3

  # Read recent progress
  local recent_progress=""
  if [[ -f "$PROGRESS_FILE" ]] && [[ -s "$PROGRESS_FILE" ]]; then
    recent_progress=$(tail -30 "$PROGRESS_FILE")
  fi

  # Read template
  local template
  template=$(<"$PROMPT_TEMPLATE")

  # Substitute variables
  template="${template//\{\{iteration\}\}/$iteration}"
  template="${template//\{\{max_iterations\}\}/$MAX_ITERATIONS}"
  template="${template//\{\{prd_file\}\}/$RESOLVED_PRD_FILE}"
  template="${template//\{\{original_prompt\}\}/$PROMPT}"
  template="${template//\{\{prd_passing\}\}/$prd_passing}"
  template="${template//\{\{prd_total\}\}/$prd_total}"
  template="${template//\{\{completion_promise\}\}/$COMPLETION_PROMISE}"
  template="${template//\{\{recent_progress\}\}/$recent_progress}"
  template="${template//\{\{architecture_file\}\}/$ARCHITECTURE_FILE}"

  # Handle PRD conditionals
  if [[ -n "$RESOLVED_PRD_FILE" ]]; then
    # Remove if_prd markers, keep content
    template=$(echo "$template" | sed 's/{{#if_prd}}//g; s/{{\/if_prd}}//g')
    # Remove if_no_prd blocks entirely
    template=$(echo "$template" | sed '/{{#if_no_prd}}/,/{{\/if_no_prd}}/d')
  else
    # Remove if_no_prd markers, keep content
    template=$(echo "$template" | sed 's/{{#if_no_prd}}//g; s/{{\/if_no_prd}}//g')
    # Remove if_prd blocks entirely
    template=$(echo "$template" | sed '/{{#if_prd}}/,/{{\/if_prd}}/d')
  fi

  echo "$template"
}

# Extract progress from output
extract_progress() {
  local output="$1"
  echo "$output" | perl -0777 -ne 'print $1 if /<progress>(.*?)<\/progress>/s' 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Check for completion promise
check_completion() {
  local output="$1"
  local promise_text
  promise_text=$(echo "$output" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$promise_text" ]] && [[ "$promise_text" = "$COMPLETION_PROMISE" ]]; then
    return 0
  fi
  return 1
}

# Main loop
main() {
  # Background mode: spawn self with --foreground and exit
  if [[ "$FOREGROUND" != "true" ]]; then
    LOG_FILE=".claude/ralph-loop.log"
    mkdir -p .claude

    # Re-run with original args plus --foreground
    nohup setsid "$0" "${ORIGINAL_ARGS[@]}" --foreground > "$LOG_FILE" 2>&1 &
    BG_PID=$!
    echo "$BG_PID" > .claude/ralph-loop.pid

    echo "========================================"
    echo " Ralph Loop Started (Background)"
    echo "========================================"
    echo ""
    echo "PID: $BG_PID"
    echo ""
    echo "Monitor:"
    echo "  tail -f .claude/ralph-loop.log"
    echo ""
    echo "Check progress:"
    echo "  cat .claude/ralph-progress.txt"
    echo ""
    echo "Check state:"
    echo "  cat .claude/ralph-loop-state.json"
    echo ""
    echo "Stop:"
    echo "  kill \$(cat .claude/ralph-loop.pid)"
    echo ""
    exit 0
  fi

  echo "========================================"
  echo " Ralph Loop - Fresh Context Per Iteration"
  echo "========================================"
  echo ""
  echo "Prompt: $PROMPT"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Completion promise: $COMPLETION_PROMISE"
  if [[ -n "$RESOLVED_PRD_FILE" ]]; then
    echo "PRD: $RESOLVED_PRD_FILE"
  fi
  echo ""
  echo "Starting loop... (Ctrl+C to stop)"
  echo ""

  # Initialize state
  init_state
  touch "$PROGRESS_FILE"

  local iteration=1
  local prd_passing=0
  local prd_total=0

  if [[ -n "$RESOLVED_PRD_FILE" ]] && command -v jq &> /dev/null; then
    prd_total=$(jq '.features | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
    prd_passing=$(jq '[.features[] | select(.passes == true)] | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")
  fi

  while true; do
    echo "----------------------------------------"
    echo " Iteration $iteration / $MAX_ITERATIONS"
    if [[ -n "$RESOLVED_PRD_FILE" ]]; then
      echo " PRD: $prd_passing / $prd_total features passing"
    fi
    echo "----------------------------------------"

    # Build the prompt for this iteration
    local iteration_prompt
    iteration_prompt=$(build_iteration_prompt "$iteration" "$prd_total" "$prd_passing")

    # Run Claude with fresh context
    echo ""
    echo "Running Claude (fresh context)..."
    echo ""

    local output
    local exit_code=0

    if [[ "$VERBOSE" == "true" ]]; then
      # Stream output in verbose mode
      output=$(claude -p "$iteration_prompt" --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Task,TodoWrite" 2>&1) || exit_code=$?
      echo "$output"
    else
      # Capture output quietly
      output=$(claude -p "$iteration_prompt" --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Task,TodoWrite" 2>&1) || exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
      echo "Warning: Claude exited with code $exit_code"
    fi

    # Extract and save progress
    local progress_entry
    progress_entry=$(extract_progress "$output")

    if [[ -n "$progress_entry" ]]; then
      {
        printf '=== Iteration %d (%s) ===\n' "$iteration" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s\n\n' "$progress_entry"
      } >> "$PROGRESS_FILE"

      echo ""
      echo "Progress saved:"
      echo "$progress_entry"
    fi

    # Check for completion
    if check_completion "$output"; then
      echo ""
      echo "========================================"
      echo " COMPLETE!"
      echo "========================================"
      echo ""
      echo "Detected: <promise>$COMPLETION_PROMISE</promise>"
      mark_state_complete
      break
    fi

    # Update PRD status
    if [[ -n "$RESOLVED_PRD_FILE" ]] && command -v jq &> /dev/null; then
      prd_passing=$(jq '[.features[] | select(.passes == true)] | length' "$RESOLVED_PRD_FILE" 2>/dev/null || echo "0")

      # Check if all PRD features pass
      if [[ "$prd_total" -gt 0 ]] && [[ "$prd_passing" -eq "$prd_total" ]]; then
        echo ""
        echo "========================================"
        echo " All PRD features pass! ($prd_passing/$prd_total)"
        echo "========================================"
        mark_state_complete
        break
      fi
    fi

    # Check max iterations
    if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $iteration -ge $MAX_ITERATIONS ]]; then
      echo ""
      echo "========================================"
      echo " Max iterations reached ($MAX_ITERATIONS)"
      echo "========================================"
      jq '.status = "max_iterations"' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
      break
    fi

    # Update state and continue
    iteration=$((iteration + 1))
    update_state_iteration "$iteration" "$prd_passing"

    echo ""
    echo "Continuing to iteration $iteration..."
    echo ""
  done

  echo ""
  echo "Loop finished."
  echo "Progress log: $PROGRESS_FILE"
  echo "State file: $STATE_FILE"
}

# Run main
main
