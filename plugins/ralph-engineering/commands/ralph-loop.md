---
description: "Start Ralph Wiggum loop in current session"
argument-hint: "[PROMPT] [--max-iterations N] [--completion-promise TEXT] [--prd FILE]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh *)", "Read", "Write", "Edit", "Bash(git *)", "Bash(pnpm *)"]
hide-from-slash-command-tool: "true"
---

# Ralph Loop Command

Execute the setup script to initialize the Ralph loop by running this Bash command:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS
```

After running the setup script, follow the workflow below.

## PRD-Driven Development Workflow

When a PRD file exists (auto-detected at `./plans/prd.json` or specified via `--prd`), follow this structured workflow for each iteration:

### 1. Create Feature Branch (First Iteration Only)

On the first iteration, create a feature branch:
```bash
git checkout -b feature/prd-implementation
```

### 2. Read and Analyze the PRD

Read the PRD file and identify all features with `passes: false`:
- Parse `./plans/prd.json` (or the specified PRD file)
- List all incomplete features
- Understand dependencies between features

### 3. Select Highest-Priority Feature

Choose ONE feature to work on based on priority:
- **Dependencies first**: If feature B depends on feature A, complete A first
- **Foundation before polish**: Core functionality before UI enhancements
- **Not necessarily first in list**: Use your judgment to pick the most impactful next step

### 4. Implement the Single Feature

Focus ONLY on the selected feature:
- Implement the functionality described in the feature
- Follow the verification steps as your implementation guide
- Do NOT work on other features in this iteration

### 5. Verify with Tests and Type Checking

Before marking the feature complete, verify:
```bash
pnpm typecheck
pnpm test
```

Both must pass. If they fail, fix the issues before proceeding.

### 6. Update the PRD

Once the feature is verified working:
- Read the current PRD
- Update ONLY the `passes` field for the completed feature from `false` to `true`
- Write the updated PRD back to the file

**CRITICAL RULES:**
- NEVER edit or remove feature definitions
- NEVER add new features
- ONLY change `passes: false` to `passes: true`

### 7. Commit the Feature

Create a git commit for the completed feature:
```bash
git add -A
git commit -m "feat: <feature description>"
```

### 8. Output Progress Summary

Before ending each iteration, output a brief progress summary in `<progress>` tags:

```
<progress>
- What you accomplished this iteration
- Current state (tests passing/failing, build status)
- Any blockers or issues encountered
- Suggested next steps
</progress>
```

This progress is automatically captured and shown to you in the next iteration, helping you quickly get oriented without re-exploring the codebase.

### 9. Check for Completion

After updating the PRD, check if all features are complete:
- If ALL features have `passes: true`, output: `<promise>COMPLETE</promise>`
- If features remain with `passes: false`, simply exit (the loop will continue)

## Important Rules

### Single Feature Per Iteration
You must work on exactly ONE feature per iteration. This ensures:
- Focused, quality implementation
- Clear git history
- Incremental progress tracking

### Completion Promise
If a completion promise is set (default: "COMPLETE" when using PRD), you may ONLY output it when:
- ALL PRD features have `passes: true`
- The statement is completely and unequivocally TRUE

Do NOT output false promises to escape the loop, even if you think you're stuck.

### PRD Immutability
The PRD is your contract. You may:
- ✅ Change `passes: false` to `passes: true`
- ❌ Edit feature descriptions
- ❌ Remove features
- ❌ Add new features
- ❌ Change `passes: true` back to `false`

## Example Iteration

```
Iteration 1:
1. git checkout -b feature/prd-implementation
2. Read ./plans/prd.json - found 5 features, 0 passing
3. Selected feat_002 (login functionality) - required before feat_003 (dashboard)
4. Implemented login form and authentication
5. pnpm typecheck ✓, pnpm test ✓
6. Updated PRD: feat_002.passes = true
7. git commit -m "feat: implement user login"
8. Output progress summary:
   <progress>
   - Implemented login form and JWT authentication
   - Tests: 15/15 passing, typecheck clean
   - Next: dashboard component (feat_003)
   </progress>
9. 1/5 features complete - more work needed, exiting...

Iteration 2:
(Sees progress summary from iteration 1 in system message)
1. Read ./plans/prd.json - found 5 features, 1 passing
2. Selected feat_003 (dashboard) - login dependency satisfied
3. Implemented dashboard component
...
```

## Running Without PRD

If no PRD exists and no `--prd` option is provided, ralph-loop works as before:
- Requires a PROMPT argument
- Loops until completion promise is output or max iterations reached
- No structured feature workflow

**Important:** Even without a PRD, you should still output a `<progress>` summary at the end of each iteration to help your next iteration understand what was accomplished.
