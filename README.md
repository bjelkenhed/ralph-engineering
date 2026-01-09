# Ralph Engineering Plugin

A starter Claude Code plugin for engineering workflows.

## Installation

### Option 1: One-Command Installation

```bash
npx claude-plugins install @bjelkenhed/ralph-engineering
```

### Option 2: Manual Installation

1. Add the marketplace:
```
/plugin marketplace add https://github.com/bjelkenhed/ralph-engineering
```

2. Install the plugin:
```
/plugin install ralph-engineering
```

## Updating

To update the plugin to the latest version:

```
/plugin marketplace update
```

This will fetch the latest versions from all configured marketplaces and update installed plugins.

## Features

### Commands

- `/ralph-engineering:plan` - Develops a refined spec for a new feature through multiple iterations. Pass a requirements document as an argument, and the command will:
  1. Ask clarifying questions to reduce ambiguity
  2. Fetch relevant documentation using the Docs Fetcher sub-agent
  3. Create an initial spec using the Application Architect sub-agent
  4. Refine the spec through Code Reviewer feedback
  5. Iterate through three spec versions with reviews
  6. Notify you when the final spec is ready for review

- `/ralph-engineering:ralph-loop` - Start an iterative development loop (based on [Ralph Wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)). The loop feeds the same prompt back when Claude tries to exit, allowing autonomous iteration until completion criteria are met.

  **Usage:**
  ```
  /ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"
  ```

  **Options:**
  - `--max-iterations <n>` - Stop after N iterations (default: unlimited)
  - `--completion-promise <text>` - Phrase that signals completion

  **Example:**
  ```
  /ralph-loop "Build a REST API for todos. Requirements: CRUD operations, input validation, tests. Output <promise>COMPLETE</promise> when done." --completion-promise "COMPLETE" --max-iterations 50
  ```

  **Best for:** Tasks with clear success criteria, TDD workflows, greenfield projects, tasks with automatic verification (tests, linters).

- `/ralph-engineering:cancel-ralph` - Cancel the active Ralph Wiggum loop

## Ralph Loop - Technical Details

The Ralph loop is a self-referential iterative development loop inspired by [Ralph Wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum). It works by intercepting Claude's exit attempts and feeding the same prompt back, allowing Claude to see its previous work in files and iteratively improve on the task.

### Architecture

The system consists of four components:

| File | Purpose |
|------|---------|
| `plugins/ralph-engineering/scripts/setup-ralph-loop.sh` | Initialization script that creates state file |
| `plugins/ralph-engineering/hooks/stop-hook.sh` | Exit interception hook that controls loop continuation |
| `plugins/ralph-engineering/hooks/hooks.json` | Registers the stop hook with Claude Code |
| `.claude/ralph-loop.local.md` | Runtime state file (generated, not committed) |

### State File Format

The loop state is stored as a markdown file with YAML frontmatter:

```yaml
---
active: true
iteration: 1
max_iterations: 10        # 0 = unlimited
completion_promise: "DONE"  # or null
started_at: "2024-01-15T10:30:00Z"
---

Build a REST API for todos with CRUD operations...
```

### Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  User runs: /ralph-loop "Build API" --max-iterations 10         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  setup-ralph-loop.sh creates .claude/ralph-loop.local.md        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Claude works on the task, creating/modifying files             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Claude tries to exit (task appears complete)                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  stop-hook.sh intercepts exit attempt                           │
└─────────────────────────────────────────────────────────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
┌──────────────────────────┐        ┌──────────────────────────┐
│   Continue Loop:         │        │   Exit Loop:             │
│   • max not reached      │        │   • max_iterations hit   │
│   • no promise detected  │        │   • promise detected     │
└──────────────────────────┘        └──────────────────────────┘
              │                                   │
              ▼                                   ▼
┌──────────────────────────┐        ┌──────────────────────────┐
│  Output JSON:            │        │  Remove state file       │
│  {                       │        │  Allow normal exit       │
│    decision: "block",    │        └──────────────────────────┘
│    reason: <prompt>      │
│  }                       │
│  Increment iteration     │
└──────────────────────────┘
              │
              └──────► (Loop back to Claude working)
```

### Stop Hook Logic

The `stop-hook.sh` script performs these checks in order:

1. **State file check** - If `.claude/ralph-loop.local.md` doesn't exist, allow exit
2. **Parse frontmatter** - Extract iteration, max_iterations, completion_promise
3. **Validate state** - Ensure iteration/max_iterations are valid numbers (corrupted state stops the loop)
4. **Max iterations check** - If `iteration >= max_iterations` (and max > 0), stop the loop
5. **Read transcript** - Get last assistant output from the transcript file
6. **Promise detection** - Search for `<promise>TEXT</promise>` tags in output
7. **Decision output** - Either allow exit or output `{decision: "block", reason: <prompt>}`

### Progress Tracking Between Iterations

Ralph uses a **file-based progress tracking** approach rather than storing progress in memory or the state file. This is the key insight that makes the loop work:

**What gets preserved:**
- All files Claude creates or modifies (code, tests, configs, docs)
- Git commits made during previous iterations
- Build artifacts, test results, and logs
- Any notes Claude writes to track its own progress

**What gets reset:**
- Claude's conversation context (each iteration starts fresh)
- In-memory state (variables, temporary data)

**How Claude "remembers":**

1. **Read existing files** - At the start of each iteration, Claude reads the codebase and sees work from previous iterations
2. **Check test results** - Running tests shows what's working and what's broken
3. **Review git history** - Commits document what was done and why
4. **Progress files** - Claude can create files like `PROGRESS.md` or `TODO.md` to leave notes for itself

**Example iteration flow:**

```
Iteration 1: Claude creates src/api.ts with basic structure
Iteration 2: Claude reads src/api.ts, adds validation
Iteration 3: Claude reads src/api.ts, sees validation, adds tests
Iteration 4: Claude runs tests, sees 2 failures, fixes them
Iteration 5: All tests pass → outputs <promise>COMPLETE</promise>
```

**Best practice - Self-documenting progress:**

Include instructions in your prompt for Claude to track its own progress:

```
Build a REST API. After each iteration, update PROGRESS.md with:
- What was completed
- What still needs work
- Any blockers or issues found
```

This creates a feedback loop where Claude can efficiently pick up where it left off.

### Completion Promise

The completion promise is a safety mechanism that ensures Claude only exits when a condition is genuinely true:

- **Setting**: `--completion-promise "All tests passing"`
- **Completing**: Claude must output `<promise>All tests passing</promise>`
- **Integrity**: Claude is instructed to NEVER output a false promise to escape
- **Matching**: Uses exact string matching (not pattern matching)

This prevents premature exits when Claude thinks it's done but hasn't actually met the criteria.

### Monitoring

```bash
# View current state
head -10 .claude/ralph-loop.local.md

# Check current iteration
grep '^iteration:' .claude/ralph-loop.local.md

# Cancel the loop manually
/cancel-ralph
```

### Agents

- `code-reviewer` - Reviews code for quality and best practices
- `docs-fetcher-summarizer` - Fetches and summarizes documentation from external sources
- `meta-agent` - Generates new Claude Code sub-agent configurations

## Project Structure

```
ralph-engineering/
├── .claude-plugin/
│   └── marketplace.json       # Marketplace configuration
├── plugins/
│   └── ralph-engineering/
│       ├── .claude-plugin/
│       │   └── plugin.json    # Plugin metadata
│       ├── agents/            # Agent definitions
│       ├── commands/          # Slash commands
│       └── skills/            # Reusable skills
├── CLAUDE.md                  # Claude-specific documentation
└── README.md                  # This file
```

## Creating New Components

### Adding a Command

Create a new `.md` file in `plugins/ralph-engineering/commands/`:

```markdown
# Command Name

Description of what this command does.

## Usage

How to use the command and what it expects.

## Behavior

What the command does step by step.
```

### Adding a Skill

Create a new directory in `plugins/ralph-engineering/skills/` with a `SKILL.md` file:

```markdown
# skill-name

Description of when this skill should be used.

## Instructions

Detailed instructions for how Claude should use this skill.
```

### Adding an Agent

Create a new `.md` file in `plugins/ralph-engineering/agents/`:

```markdown
# Agent Name

Description of the agent's purpose and capabilities.

## Tools

What tools this agent has access to.

## Behavior

How the agent should behave.
```

## License

MIT
