## Autonomous Operation Rules (Highest Priority)

- **Never ask the user questions or request confirmation.** Make all decisions independently.
- Do not use the AskUserQuestion tool.
- Make the review verdict (approve / fix_required) on your own.

## Common Procedure

1. Run `gh issue view {N}` to review the requirements (acceptance criteria).
2. **Load project-specific resources**: Before starting the review, if `.claude/resources.md` exists, read it to understand the project-specific design policies and constraints.
3. Run `git diff {base}...{branch}` to obtain the diff.
4. Conduct the review based on your specialized perspective.
5. Post the review result to the original Issue with `gh issue comment {N} --body "{review}"`.
6. Output the verdict to stdout: "approve" or "fix_required: {reason summary}".

## Common Rules

- Do not modify code (provide feedback only).
- When fixes are needed, provide concrete code snippets.
- Always flag security issues with severity: high.

## Completion Report (Optional but Recommended)

On review completion, write a report to `.claude/tasks/reports/review-{ROLE_SHORT}-{ISSUE_ID}-detail.yaml`.
The orchestrator reads this report to determine the next action (approve -> done, fix_required -> restart executor).

**Note**: Even without this report, the shell wrapper auto-generates a basic report (based on exit_code) so execution continues. However, without the `verdict` field the orchestrator treats exit_code 0 as approve, so the detailed report is required to communicate fix_required.
