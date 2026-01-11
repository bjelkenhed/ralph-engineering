---
description: "Start Ralph Wiggum loop (fresh context per iteration)"
argument-hint: "[PROMPT] [--max-iterations N] [--completion-promise TEXT] [--prd FILE] [--verbose]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ralph-loop.sh *)"]
hide-from-slash-command-tool: "true"
---

# Ralph Loop Command

Execute the loop script to start the external orchestrator:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph-loop.sh" $ARGUMENTS
```

This command runs Claude in a loop where each iteration gets **fresh context**.
This follows Anthropic's recommended pattern for long-running agents.

By default, runs in **background mode** to avoid timeout limits. The command returns immediately with monitoring instructions.

## Background Mode (Default)

When you run `/ralph-loop`, it:
1. Spawns a background process that runs independently
2. Returns immediately with PID and monitoring instructions
3. Writes output to `.claude/ralph-loop.log`
4. Stores PID in `.claude/ralph-loop.pid`

**Monitoring:**
- `tail -f .claude/ralph-loop.log` - Watch live output
- `cat .claude/ralph-progress.txt` - See iteration summaries
- `cat .claude/ralph-loop-state.json` - Check current state
- `kill $(cat .claude/ralph-loop.pid)` - Stop the loop

**Foreground mode:** Use `--foreground` to run in blocking mode (subject to 10-minute timeout).

## How It Works

Unlike `/ralph-session` (which keeps the same context), `/ralph-loop`:

1. **External Orchestrator**: A bash script runs `claude -p` in a loop
2. **Fresh Context**: Each iteration starts a new Claude session
3. **State via Files**: Progress is passed via `.claude/ralph-progress.txt`
4. **Git History**: Agent reads commits to understand previous work

## Key Differences

| Feature | `/ralph-loop` | `/ralph-session` |
|---------|---------------|------------------|
| Context | Fresh each iteration | Accumulates |
| Orchestration | External bash loop | Stop hook |
| State | Files only | Memory + files |
| Stop method | Ctrl+C | Completion promise only |

## When to Use

Use `/ralph-loop` when:
- Tasks are long-running (many iterations)
- You want clean rollback points (git commits)
- Context exhaustion is a concern
- You need to inspect/modify state between iterations

Use `/ralph-session` when:
- You want the agent to remember previous iterations
- Tasks benefit from accumulated context
- You prefer not to have external tooling

## PRD-Driven Development

When a PRD exists, each iteration:
1. Reads the PRD to find incomplete features
2. Works on ONE feature
3. Commits the changes
4. Updates PRD: `passes: false` → `passes: true`
5. Outputs `<progress>` summary
6. Loop continues until all features pass
