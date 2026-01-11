#!/bin/bash

# Ralph PRD Setup Script
# Merges permissions template for the PRD wizard

set -euo pipefail

# Get script directory to find template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/settings.ralph-prd.json"

# Function to merge ralph-prd permissions into settings.local.json
merge_permissions() {
  local settings_file=".claude/settings.local.json"
  local temp_file

  # Check if template exists
  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Warning: Permissions template not found: $TEMPLATE_FILE" >&2
    return 0
  fi

  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo "Warning: jq not installed - cannot merge permissions automatically" >&2
    return 0
  fi

  # Validate template has expected structure
  if ! jq -e '.permissions.allow' "$TEMPLATE_FILE" &>/dev/null; then
    echo "Warning: Template missing .permissions.allow - skipping merge" >&2
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
    echo "Warning: Failed to create temp file - skipping merge" >&2
    return 0
  }

  # Merge permissions arrays (remove duplicates)
  if ! jq -s '
    .[0].permissions.allow as $existing |
    .[1].permissions.allow as $template |
    .[0] | .permissions.allow = ($existing + $template | unique)
  ' "$settings_file" "$TEMPLATE_FILE" > "$temp_file" 2>&1; then
    echo "Warning: Failed to merge permissions" >&2
    rm -f "$temp_file"
    return 0
  fi

  # Validate output is valid JSON
  if ! jq -e '.permissions.allow' "$temp_file" &>/dev/null; then
    echo "Warning: Merge produced invalid output - skipping" >&2
    rm -f "$temp_file"
    return 0
  fi

  # Atomic move
  mv "$temp_file" "$settings_file" || {
    echo "Warning: Failed to write $settings_file" >&2
    rm -f "$temp_file"
    return 0
  }

  echo "Auto-approved permissions for ralph-prd"
}

# Merge ralph-prd permissions into settings
merge_permissions

# Pass through all arguments as the project description
if [[ $# -gt 0 ]]; then
  echo "Project description: $*"
fi
