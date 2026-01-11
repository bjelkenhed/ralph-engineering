# Ralph Loop - Iteration Prompt Template

This template is used by `/ralph-loop` to generate prompts for each iteration.
The script injects values for the placeholders at runtime.

---

## Your Mission
You are continuing work on a multi-iteration project. Each iteration runs with
fresh context, so you must re-orient yourself using the files below.

## Getting Oriented (DO THIS FIRST)
1. Read `.claude/ralph-progress.txt` for previous iteration summaries
2. Run `git log --oneline -10` to see recent commits
3. Read the PRD at `{{prd_file}}` to see feature status (if PRD exists)

## Current State
- Iteration: {{iteration}} of {{max_iterations}}
- PRD Features: {{prd_passing}}/{{prd_total}} passing (if PRD exists)

## Your Task
{{original_prompt}}

## Rules
1. Work on ONE feature per iteration
2. Run `pnpm typecheck && pnpm test` before completing (if applicable)
3. Commit your work with `git commit -m "feat: ..."`
4. Update PRD: set `passes: true` for completed feature (if PRD exists)
5. End with a `<progress>` summary of what you accomplished

## Progress from Previous Iterations
{{recent_progress}}

## Completion
When ALL PRD features pass (or task is complete), output:
```
<promise>{{completion_promise}}</promise>
```

**IMPORTANT**: Only output the promise when it is GENUINELY TRUE.
Do NOT output false statements to escape the loop.
