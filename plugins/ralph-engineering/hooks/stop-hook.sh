#!/bin/bash

# Ralph Wiggum Stop Hook
# Prevents session exit when a ralph-loop is active
# Feeds Claude's output back as input to continue the loop

set -euo pipefail

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)

# Check if ralph-loop is active
RALPH_STATE_FILE=".claude/ralph-loop.local.md"
RALPH_PROGRESS_FILE=".claude/ralph-progress.txt"

# Helper function to archive progress and clean up state, then exit
cleanup_and_exit() {
  if [[ -f "$RALPH_PROGRESS_FILE" ]]; then
    if [[ -s "$RALPH_PROGRESS_FILE" ]]; then
      # File has content - archive it with timestamp (UTC for consistency)
      ARCHIVE_FILE=".claude/ralph-progress-$(date -u +%Y%m%dT%H%M%SZ).txt"
      mv "$RALPH_PROGRESS_FILE" "$ARCHIVE_FILE"
      echo "📁 Progress archived to $ARCHIVE_FILE"
    else
      # Empty file - just remove it
      rm -f "$RALPH_PROGRESS_FILE"
    fi
  fi
  rm -f "$RALPH_STATE_FILE"
  exit 0
}

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop - allow exit
  exit 0
fi

# Parse markdown frontmatter (YAML between ---) and extract values
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
# Extract completion_promise and strip surrounding quotes if present
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
# Extract prd_file and strip surrounding quotes if present
PRD_FILE=$(echo "$FRONTMATTER" | grep '^prd_file:' | sed 's/prd_file: *//' | sed 's/^"\(.*\)"$/\1/')

# Validate numeric fields before arithmetic operations
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: State file corrupted" >&2
  echo "   File: $RALPH_STATE_FILE" >&2
  echo "   Problem: 'iteration' field is not a valid number (got: '$ITERATION')" >&2
  echo "" >&2
  echo "   This usually means the state file was manually edited or corrupted." >&2
  echo "   Ralph loop is stopping. Run /ralph-loop again to start fresh." >&2
  cleanup_and_exit
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: State file corrupted" >&2
  echo "   File: $RALPH_STATE_FILE" >&2
  echo "   Problem: 'max_iterations' field is not a valid number (got: '$MAX_ITERATIONS')" >&2
  echo "" >&2
  echo "   This usually means the state file was manually edited or corrupted." >&2
  echo "   Ralph loop is stopping. Run /ralph-loop again to start fresh." >&2
  cleanup_and_exit
fi

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached."
  cleanup_and_exit
fi

# Check PRD status if PRD file is set
PRD_STATUS=""
PRD_TOTAL=0
PRD_PASSING=0
if [[ -n "$PRD_FILE" ]] && [[ "$PRD_FILE" != "null" ]] && [[ -f "$PRD_FILE" ]]; then
  PRD_TOTAL=$(jq '.features | length' "$PRD_FILE" 2>/dev/null || echo "0")
  PRD_PASSING=$(jq '[.features[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
  PRD_STATUS="PRD: $PRD_PASSING/$PRD_TOTAL"

  # Auto-complete if all features pass
  if [[ "$PRD_TOTAL" -gt 0 ]] && [[ "$PRD_PASSING" -eq "$PRD_TOTAL" ]]; then
    echo "✅ Ralph loop: All PRD features pass! ($PRD_PASSING/$PRD_TOTAL)"
    cleanup_and_exit
  fi
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Ralph loop: Transcript file not found" >&2
  echo "   Expected: $TRANSCRIPT_PATH" >&2
  echo "   This is unusual and may indicate a Claude Code internal issue." >&2
  echo "   Ralph loop is stopping." >&2
  cleanup_and_exit
fi

# Read last assistant message from transcript (JSONL format - one JSON per line)
# First check if there are any assistant messages
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Ralph loop: No assistant messages found in transcript" >&2
  echo "   Transcript: $TRANSCRIPT_PATH" >&2
  echo "   This is unusual and may indicate a transcript format issue" >&2
  echo "   Ralph loop is stopping." >&2
  cleanup_and_exit
fi

# Extract last assistant message with explicit error handling
LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
if [[ -z "$LAST_LINE" ]]; then
  echo "⚠️  Ralph loop: Failed to extract last assistant message" >&2
  echo "   Ralph loop is stopping." >&2
  cleanup_and_exit
fi

# Parse JSON with error handling
LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>&1)

# Check if jq succeeded (capture exit status immediately)
JQ_STATUS=$?
if [[ $JQ_STATUS -ne 0 ]]; then
  echo "⚠️  Ralph loop: Failed to parse assistant message JSON" >&2
  echo "   Error: $LAST_OUTPUT" >&2
  echo "   This may indicate a transcript format issue" >&2
  echo "   Ralph loop is stopping." >&2
  cleanup_and_exit
fi

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Ralph loop: Assistant message contained no text content" >&2
  echo "   Ralph loop is stopping." >&2
  cleanup_and_exit
fi

# Check for completion promise (only if set)
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Extract text from <promise> tags using Perl for multiline support
  # -0777 slurps entire input, s flag makes . match newlines
  # .*? is non-greedy (takes FIRST tag), whitespace normalized
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  # Use = for literal string comparison (not pattern matching)
  # == in [[ ]] does glob pattern matching which breaks with *, ?, [ characters
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>"
    cleanup_and_exit
  fi
fi

# Not complete - continue loop with SAME PROMPT
NEXT_ITERATION=$((ITERATION + 1))

# Extract progress from <progress> tags and append to progress file
# Use print-if-match pattern to avoid outputting original string when no match
PROGRESS_ENTRY=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'print $1 if /<progress>(.*?)<\/progress>/s' 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ -n "$PROGRESS_ENTRY" ]]; then
  {
    printf '=== Iteration %d (%s) ===\n' "$ITERATION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n\n' "$PROGRESS_ENTRY"
  } >> "$RALPH_PROGRESS_FILE"
fi

# Read recent progress for system message (last ~20 lines)
RECENT_PROGRESS=""
if [[ -f "$RALPH_PROGRESS_FILE" ]] && [[ -s "$RALPH_PROGRESS_FILE" ]]; then
  RECENT_PROGRESS=$(tail -20 "$RALPH_PROGRESS_FILE")
fi

# Extract prompt (everything after the closing ---)
# Skip first --- line, skip until second --- line, then print everything after
# Use i>=2 instead of i==2 to handle --- in prompt content
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  Ralph loop: State file corrupted or incomplete" >&2
  echo "   File: $RALPH_STATE_FILE" >&2
  echo "   Problem: No prompt text found" >&2
  echo "" >&2
  echo "   This usually means:" >&2
  echo "     • State file was manually edited" >&2
  echo "     • File was corrupted during writing" >&2
  echo "" >&2
  echo "   Ralph loop is stopping. Run /ralph-loop again to start fresh." >&2
  cleanup_and_exit
fi

# Update iteration in frontmatter (portable across macOS and Linux)
# Create temp file, then atomically replace
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# Build system message with iteration count, PRD status, and completion promise info
SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION"

# Add PRD status if available
if [[ -n "$PRD_STATUS" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | $PRD_STATUS"
fi

# Add completion promise info
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | To stop: <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE)"
else
  SYSTEM_MSG="$SYSTEM_MSG | No completion promise - loop runs until PRD complete or max iterations"
fi

# Add recent progress context if available
if [[ -n "$RECENT_PROGRESS" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG

Recent progress:
$RECENT_PROGRESS"
fi

# Output JSON to block the stop and feed prompt back
# The "reason" field contains the prompt that will be sent back to Claude
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

# Exit 0 for successful hook execution
exit 0