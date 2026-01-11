---
description: "Cancel active Ralph Wiggum session"
allowed-tools: ["Bash(test -f .claude/ralph-session.local.md:*)", "Bash(rm .claude/ralph-session.local.md)", "Read(.claude/ralph-session.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel Ralph

To cancel the Ralph session:

1. Check if `.claude/ralph-session.local.md` exists using Bash: `test -f .claude/ralph-session.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Ralph session found."

3. **If EXISTS**:
   - Read `.claude/ralph-session.local.md` to get the current iteration number from the `iteration:` field
   - Remove the file using Bash: `rm .claude/ralph-session.local.md`
   - Report: "Cancelled Ralph session (was at iteration N)" where N is the iteration value
