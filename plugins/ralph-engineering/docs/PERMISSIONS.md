# Running Ralph Loop Autonomously

This guide explains how to configure permissions so the ralph-loop can run without constant permission prompts.

## Automatic Permission Setup

**As of v1.0.11**, ralph-loop automatically merges safe permissions into your `.claude/settings.local.json` when you start a loop. This prevents the loop from getting stuck waiting for permission prompts.

When you run `/ralph-loop`, the setup script:
1. Reads permissions from `templates/settings.ralph-loop.json`
2. Merges them into `.claude/settings.local.json` (creates if missing)
3. Removes duplicates to keep the file clean
4. Uses atomic writes to prevent corruption

This means you can simply run `/ralph-loop` and the necessary permissions will be configured automatically.

## Quick Start

**Just run it** (permissions auto-configured):
```bash
/ralph-loop Build a REST API --max-iterations 10
```

The loop will auto-approve safe operations like git, npm, file reads/writes, etc.

**For complete autonomy** (use in isolated environment only):
```bash
claude --dangerously-skip-permissions
```

**For maximum isolation** (devcontainer):
```bash
# Use the provided devcontainer template
cp -r plugins/ralph-engineering/templates/.devcontainer .devcontainer

# Open in VS Code and reopen in container, then:
claude --dangerously-skip-permissions
```

## Why Permissions Matter for Ralph Loop

Ralph-loop is designed to run autonomously, iterating on tasks without human intervention. However, Claude Code requires permission prompts for potentially dangerous operations like:
- Running shell commands
- Reading/writing files
- Making web requests

**The Problem**: If the loop encounters a permission prompt, it gets stuck waiting for user input. This breaks the autonomous workflow.

**The Solution**: Ralph-loop now automatically configures permissions when started, ensuring common safe operations are pre-approved. This allows the loop to run uninterrupted while still maintaining security boundaries.

## Permission Options Explained

### Option 1: `--dangerously-skip-permissions`

Bypasses ALL permission prompts. Use only in:
- Devcontainers or isolated environments
- CI/CD pipelines
- Sandboxed environments

```bash
claude --dangerously-skip-permissions
```

**Risk**: Can execute any command without confirmation. Always use with isolation.

### Option 2: Automatic Permission Merging (Default)

Ralph-loop automatically configures permissions when started. The template at `templates/settings.ralph-loop.json` contains:

```json
{
  "permissions": {
    "defaultMode": "dontAsk",
    "allow": [
      "Bash(git *)",
      "Bash(pnpm *)",
      "Bash(npm *)",
      "Bash(yarn *)",
      "Bash(npx *)",
      "Bash(tsc *)",
      "Bash(eslint *)",
      "Bash(prettier *)",
      "Bash(vitest *)",
      "Bash(jest *)",
      "Bash(cargo *)",
      "Bash(make *)",
      "Bash(pip *)",
      "Bash(poetry *)",
      "Bash(uv *)",
      "Read(**/*)",
      "Edit(**/*)",
      "Write(**/*)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Read(.env)",
      "Read(.env.*)",
      "Read(.env.local)",
      "Read(.env.production)",
      "WebFetch"
    ]
  }
}
```

These permissions are merged into `.claude/settings.local.json` when you run `/ralph-loop`.

**How it works**:
1. The setup script runs `merge_permissions()` before starting the loop
2. Existing permissions in `settings.local.json` are preserved
3. Template permissions are added (duplicates removed)
4. The merge uses atomic writes to prevent file corruption

**Requirements**:
- `jq` must be installed (shows warning if missing)
- Falls back gracefully if merge fails

**To customize**: Edit `templates/settings.ralph-loop.json` to add/remove permissions.

### Option 3: Manual Settings Allowlist

For manual control, create `.claude/settings.local.json` yourself:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(npm *)",
      "Read(**/*)",
      "Edit(**/*)",
      "Write(**/*)"
    ]
  }
}
```

**Benefits**:
- Fine-grained control over allowed commands
- Ralph-loop will merge its permissions on top of yours
- No need for `--dangerously-skip-permissions`

### Option 4: PreToolUse Hook (Auto-Approval)

This plugin includes a PreToolUse hook that auto-approves commands matching the ralph-loop's allowed-tools.

The hook is **enabled by default** and will auto-approve:
- Git commands (`git *`)
- Package manager commands (`pnpm *`, `npm *`)
- File operations (Read, Write, Edit)
- The ralph-loop setup script

To disable the hook, remove the PreToolUse section from `hooks/hooks.json`.

### Option 5: Devcontainer (Maximum Safety)

For maximum isolation, use a devcontainer:

1. Copy the template:
   ```bash
   cp -r plugins/ralph-engineering/templates/.devcontainer .devcontainer
   ```

2. Open in VS Code and click "Reopen in Container"

3. Run with skip-permissions safely:
   ```bash
   claude --dangerously-skip-permissions
   ```

**Benefits**:
- Complete isolation from host system
- Safe to use `--dangerously-skip-permissions`
- Reproducible environment

## Permission Modes

| Mode | Behavior |
|------|----------|
| `default` | Prompts for each new tool type |
| `acceptEdits` | Auto-accepts file edits for the session |
| `plan` | Read-only analysis, no modifications |
| `dontAsk` | Denies everything unless pre-approved in settings |
| `bypassPermissions` | Skips all prompts (use with caution) |

## Pattern Syntax

### Bash Patterns
```
Bash(npm run build)     # Exact match
Bash(npm run test:*)    # Prefix matching with :*
Bash(npm *)             # Wildcard matching
Bash(git * main)        # Multiple wildcards
```

### File Patterns (gitignore syntax)
```
Read(src/**)            # All files in src/
Read(~/.config/app)     # Home directory
Read(//etc/config)      # Absolute path
Edit(**/*.ts)           # All TypeScript files
```

## Troubleshooting

### Still getting permission prompts?

1. Check if `jq` is installed: `which jq` (required for auto-merge)
2. Verify `.claude/settings.local.json` was created and contains permissions
3. Check the ralph-loop startup output for merge warnings
4. Ensure the template file exists: `templates/settings.ralph-loop.json`
5. Try adding the specific permission pattern to the template

### Permission merge not working?

1. Install jq: `brew install jq` (macOS) or `apt install jq` (Linux)
2. Check for warnings in the ralph-loop startup output
3. Manually inspect `.claude/settings.local.json` for correct structure
4. Verify template file has valid JSON: `jq . templates/settings.ralph-loop.json`

### Hook not working?

1. Check that `hooks.json` includes the PreToolUse hook
2. Ensure `auto-approve.sh` is executable: `chmod +x hooks/auto-approve.sh`
3. Check hook logs for errors

### Commands still denied?

1. Check the deny list - it takes precedence over allow
2. Verify pattern syntax matches exactly
3. Try more permissive patterns temporarily to debug

## Security Considerations

- **Never commit secrets** - Always deny `.env` files
- **Use deny lists** - Block dangerous commands explicitly
- **Prefer isolation** - Use devcontainers for `--dangerously-skip-permissions`
- **Audit regularly** - Review what commands are being auto-approved

## Known Limitations

### Pattern Matching Limitations

The bash permission patterns have inherent limitations:

1. **Command chaining** - Patterns like `Bash(git *)` allow any command starting with "git ", including `git; malicious_command`. The PreToolUse hook validates against shell metacharacters, but settings allowlists do not.

2. **Inline code execution** - Commands like `python -c "malicious"` or `node -e "malicious"` can bypass restrictions. The hook blocks `-c` and `-e` flags for Python and Node.

3. **Absolute paths** - `/usr/bin/git malicious` may bypass `git *` pattern checks.

### Deny List Not Comprehensive

The deny list blocks common dangerous patterns but cannot cover all attack vectors. It is a defense-in-depth measure, not a complete security solution.

### Recommended Safeguards

1. **Always use devcontainers** for `--dangerously-skip-permissions`
2. **Keep the PreToolUse hook enabled** - it validates against shell metacharacters
3. **Review the deny list** for your specific environment
4. **Monitor command execution** via progress logs

## Community Solutions

Based on Twitter discussions, here are popular approaches:

1. **@mark_a_phelps**: Devcontainer + `--dangerously-skip-permissions`
2. **@_Uncroyable**: Custom isolated environments for "yolo mode"
3. **Multiple instances**: Some users run concurrent Claude Code instances

See the [ralph-loop repository](https://github.com/syuya2036/ralph-loop) for community implementations.
