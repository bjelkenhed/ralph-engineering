# Ralph Loop - Iteration {{iteration}} of {{max_iterations}}

## Your Mission
You are continuing work on a multi-iteration project. Each iteration runs with
fresh context, so you must re-orient yourself using the files below.

## Getting Oriented (DO THIS FIRST)
1. Read `.claude/ralph-progress.txt` for previous iteration summaries
2. Run `git log --oneline -10` to see recent commits
{{#if_prd}}3. Read the PRD at `{{prd_file}}` to see feature status{{/if_prd}}

## Current State
- Iteration: {{iteration}} of {{max_iterations}}
{{#if_prd}}- PRD Features: {{prd_passing}}/{{prd_total}} passing{{/if_prd}}

## Your Task
{{original_prompt}}

## Architecture Guidelines
Read `{{architecture_file}}` for technology stack and design principles. Follow these patterns unless the project uses different technologies.

## Rules
1. Work on ONE feature per iteration
2. Run `pnpm typecheck && pnpm test` before completing (if applicable)
3. Commit your work with `git commit -m "feat: ..."`
{{#if_prd}}4. Update PRD: set `passes: true` for completed feature{{/if_prd}}
5. End with a <progress> summary of what you accomplished

## Progress from Previous Iterations
{{recent_progress}}

## Completion
{{#if_prd}}When ALL PRD features pass, output: <promise>{{completion_promise}}</promise>{{/if_prd}}
{{#if_no_prd}}When the task is complete, output: <promise>{{completion_promise}}</promise>{{/if_no_prd}}

IMPORTANT: Only output the promise when it is GENUINELY TRUE.
