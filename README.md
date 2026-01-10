# Ralph Engineering Plugin

A Claude Code plugin for autonomous, iterative software development using Product Requirements Documents (PRDs).

## Installation

```bash
npx claude-plugins install @bjelkenhed/ralph-engineering
```

Or manually:

```
/plugin marketplace add https://github.com/bjelkenhed/ralph-engineering
/plugin install ralph-engineering
```

## Core Workflow: PRD-Driven Development

Ralph Engineering provides a two-step workflow for autonomous development:

```
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│  1. Generate PRD    │ ──▶  │  2. Run Ralph Loop  │ ──▶  │  3. Complete!       │
│  /ralph-engineering:ralph-prd         │      │  /ralph-engineering:ralph-loop        │      │  All features pass  │
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
```

### Step 1: Generate a PRD with `/ralph-engineering:ralph-prd`

The PRD wizard creates a structured JSON document with testable feature requirements:

```bash
/ralph-engineering:ralph-prd "Create a todo app inspired by Things 3"
```

The wizard will:

1. Ask clarifying questions about your project
2. Generate features with acceptance criteria
3. Let you review and refine the requirements
4. Save the PRD to `./plans/prd.json`

**Example PRD output:**

```json
{
  "name": "Todo List Application",
  "features": [
    {
      "id": "feat_001",
      "category": "functional",
      "description": "User can create a new todo item",
      "steps": [
        "Navigate to the main todo list view",
        "Click the 'Add Todo' button",
        "Enter a todo title",
        "Verify the new todo appears in the list"
      ],
      "passes": false
    }
  ]
}
```

**Key principles:**

- Features describe **user actions**, not implementation details
- Each feature has explicit **verification steps**
- The `passes` field is the only thing that can change during development
- Features cannot be added, removed, or modified once finalized

### Step 2: Run the Ralph Loop with `/ralph-engineering:ralph-loop`

The Ralph loop autonomously implements PRD features one at a time:

```bash
/ralph-engineering:ralph-loop
```

When a PRD exists at `./plans/prd.json`, Ralph automatically:

1. Creates a feature branch
2. Reads the PRD and selects the next feature to implement
3. Implements the feature
4. Runs tests and type checking
5. Updates `passes: false` → `passes: true` in the PRD
6. Commits the change
7. Repeats until all features pass

**Each iteration follows this cycle:**

```
┌──────────────────────────────────────────────────────────────┐
│                     RALPH LOOP ITERATION                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Read PRD → Find features with passes: false              │
│                           │                                  │
│                           ▼                                  │
│  2. Select ONE feature based on dependencies                 │
│                           │                                  │
│                           ▼                                  │
│  3. Implement the feature                                    │
│                           │                                  │
│                           ▼                                  │
│  4. Verify: pnpm typecheck && pnpm test                     │
│                           │                                  │
│                           ▼                                  │
│  5. Update PRD: passes: true                                 │
│                           │                                  │
│                           ▼                                  │
│  6. Commit: git commit -m "feat: <description>"              │
│                           │                                  │
│                           ▼                                  │
│  7. All features done? ──┬── No → Continue loop              │
│                          │                                   │
│                          └── Yes → Exit with COMPLETE        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## How the Ralph Loop Works

### The Self-Referential Loop

Ralph works by intercepting Claude's exit attempts. When Claude tries to exit, the stop hook:

1. Checks if the PRD has remaining incomplete features
2. If incomplete, feeds the same prompt back to Claude
3. Claude sees its previous work in files and continues

**Key insight:** Claude's conversation context resets each iteration, but all files persist. Claude "remembers" by reading:

- Code it wrote in previous iterations
- Test results showing what works
- Git history documenting progress
- The PRD showing which features are complete

### Progress Tracking

At the end of each iteration, Claude outputs a `<progress>` summary:

```
<progress>
- Implemented login form and JWT authentication
- Tests: 15/15 passing, typecheck clean
- Next: dashboard component (feat_003)
</progress>
```

This progress is captured and shown to Claude in the next iteration, helping it quickly get oriented without re-exploring the codebase.

### Completion Detection

The loop ends when:

- **All PRD features pass** - The hook checks if all `passes` fields are `true`
- **Max iterations reached** - Safety limit if specified
- **Completion promise detected** - Claude outputs `<promise>COMPLETE</promise>`

## Command Reference

### `/ralph-engineering:ralph-prd [description]`

Interactive wizard to generate a PRD.

```bash
# Start with a project description
/ralph-engineering:ralph-prd "An e-commerce checkout flow"

# Or start interactively
/ralph-engineering:ralph-prd
```

### `/ralph-engineering:ralph-loop [options]`

Start the autonomous development loop.

```bash
# With a PRD (auto-detected at ./plans/prd.json)
/ralph-engineering:ralph-loop

# With explicit PRD path
/ralph-engineering:ralph-loop --prd ./plans/my-feature.json

# Without a PRD (provide a prompt)
/ralph-engineering:ralph-loop "Build a REST API for todos" --completion-promise "DONE"

# With safety limits
/ralph-engineering:ralph-loop --max-iterations 20
```

**Options:**
| Option | Description |
|--------|-------------|
| `--prd <file>` | PRD file path (default: auto-detect `./plans/prd.json`) |
| `--prd NONE` | Disable PRD auto-detection |
| `--max-iterations <n>` | Stop after N iterations (default: unlimited) |
| `--completion-promise <text>` | Phrase that signals completion |

### `/ralph-engineering:cancel-ralph`

Cancel an active Ralph loop.

```bash
/ralph-engineering:cancel-ralph
```

## Running Without a PRD

Ralph can also work without a PRD for ad-hoc tasks:

```bash
/ralph-engineering:ralph-loop "Fix the authentication bug and ensure all tests pass" \
  --completion-promise "All tests passing" \
  --max-iterations 10
```

In this mode:

- You provide a prompt describing the task
- The completion promise defines when to stop
- Claude iterates until the promise is genuinely true

**Best for:** Bug fixes, refactoring, tasks with clear completion criteria.

## Technical Architecture

```
ralph-engineering/
├── plugins/ralph-engineering/
│   ├── commands/
│   │   ├── ralph-prd.md      # PRD generation wizard
│   │   ├── ralph-loop.md     # Loop initialization command
│   │   └── cancel-ralph.md   # Cancel active loop
│   ├── scripts/
│   │   └── setup-ralph-loop.sh   # Creates state file
│   └── hooks/
│       ├── hooks.json            # Registers stop hook
│       └── stop-hook.sh          # Exit interception logic
└── .claude/
    ├── ralph-loop.local.md       # Runtime state (generated)
    └── ralph-progress.txt        # Progress log (generated)
```

### State File Format

The loop state is stored as markdown with YAML frontmatter:

```yaml
---
active: true
iteration: 3
max_iterations: 0
completion_promise: "COMPLETE"
prd_file: "./plans/prd.json"
started_at: "2024-01-15T10:30:00Z"
---
Implement features from the PRD file at ./plans/prd.json
```

### Monitoring

```bash
# View current iteration
grep '^iteration:' .claude/ralph-engineering:ralph-loop.local.md

# View progress log
cat .claude/ralph-progress.txt

# Check PRD status
jq '.features | map(select(.passes == true)) | length' ./plans/prd.json
```

## Best Practices

### Writing Good PRDs

1. **Describe user actions, not implementation:**

   - ✓ "User can filter todos by status"
   - ✗ "Implement a filterTodos() function"

2. **Make features independently testable:**

   - ✓ "User can create a new todo item with a title"
   - ✗ "Todo CRUD operations work"

3. **Include 2-5 verification steps per feature**

4. **Order by dependencies:** Core functionality before polish

### Running Effective Loops

1. **Always set `--max-iterations`** for safety
2. **Start with a clean git state** (no uncommitted changes)
3. **Have tests and type checking configured** (`pnpm test`, `pnpm typecheck`)
4. **Monitor progress** via the progress log

## Running Autonomously (Without Permission Prompts)

By default, Claude Code prompts for permission before running commands. For true autonomous operation, you have several options:

### Quick Start (Recommended)

Copy the settings template to your project and run with `dontAsk` mode:

```bash
# Copy the settings template
cp plugins/ralph-engineering/templates/settings.ralph-loop.json .claude/settings.json

# Run Claude Code with dontAsk mode
claude --permission-mode dontAsk
```

### Option 1: Settings-Based Allowlist

The settings template pre-approves safe commands (git, pnpm, npm, file operations) and blocks dangerous ones (sudo, curl, rm -rf). Customize `.claude/settings.json` for your needs.

### Option 2: PreToolUse Hook (Enabled by Default)

This plugin includes a PreToolUse hook that auto-approves commands when the ralph-loop is active. The hook only approves commands matching the loop's allowed-tools.

### Option 3: Devcontainer (Maximum Safety)

For `--dangerously-skip-permissions` with full isolation:

```bash
# Copy the devcontainer template
cp -r plugins/ralph-engineering/templates/.devcontainer .devcontainer

# Open in VS Code, then "Reopen in Container"
# Inside the container:
claude --dangerously-skip-permissions
```

### Option 4: Skip Permissions (Use with Caution)

```bash
claude --dangerously-skip-permissions
```

Only use this in isolated environments (devcontainers, CI/CD, sandboxed VMs).

### Full Documentation

See [docs/PERMISSIONS.md](plugins/ralph-engineering/docs/PERMISSIONS.md) for:

- All permission configuration options
- Pattern syntax for allowlists
- Troubleshooting guide
- Security best practices

## License

MIT
