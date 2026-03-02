---
name: qb-dispatch
description: Launch Leader/Review Leader in tmux windows, wait for completion, read reports, and determine next action. Queen's dispatch skill for queen-bee.
---

# qb-dispatch: Leader launch + completion wait + report processing

Operational skill for the Queen to delegate issues to Leaders and Review Leaders.
Provides agent visualization via tmux windows, event-driven completion waiting, and next-action determination based on reports.

## Launching Leaders

### For issue tasks

```bash
# Implementation Leader
bash $QB_SCRIPTS_DIR/launch-leader.sh leader {issue_number} {branch}

# Review Leader
bash $QB_SCRIPTS_DIR/launch-leader.sh review-leader {issue_number} {branch}

# Fix mode (reuse existing worktree/branch)
bash $QB_SCRIPTS_DIR/launch-leader.sh leader {issue_number} {branch} fix
```

`launch-leader.sh` automatically performs the following:
- Creates a **new tmux window** for each issue (`issue-{N}` or `review-{N}`)
- Leader: Launches `claude` with git worktree isolation and appropriate environment variables / tool restrictions
- Review Leader: Launches `claude` on the main repo (read-only)
- On completion, writes a report YAML and sends a `tmux wait-for -S queen-wake` signal
- Users can simply tmux attach to see the Queen and each issue's Leader/Worker in separate windows

## Completion Waiting (Event-Driven)

### Waiting for Leader completion

```bash
# Wait with 30-minute timeout
(sleep 1800 && tmux wait-for -S queen-wake) &
TIMER_PID=$!
tmux wait-for queen-wake
kill $TIMER_PID 2>/dev/null
```

### Waiting for Review Leader completion

```bash
# Wait with 20-minute timeout
(sleep 1200 && tmux wait-for -S queen-wake) &
TIMER_PID=$!
tmux wait-for queen-wake
kill $TIMER_PID 2>/dev/null
```

### Post-wake determination

Check `.claude/tasks/reports/`:
- **New report found** — Normal completion. Proceed to report processing.
- **No report (timeout)** — Check window state.

### State check on timeout

```bash
tmux list-panes -t qb:{window_name} -F '#{@agent_label} #{pane_current_command}' 2>/dev/null
```

| State | Meaning | Action |
|-------|---------|--------|
| `claude` is running | Work still in progress | Proceed to next wait-for |
| Returned to `zsh`/`bash` | Completed but signal failed | Check report manually |
| Window has disappeared | Abnormal termination | Update status to `error` |

## Report Processing

### Report files

```
.claude/tasks/reports/
├── leader-{N}.yaml                      # Basic report written by launch-leader.sh (guaranteed)
├── leader-{N}-summary.yaml              # Detailed summary written by Leader (optional)
├── review-leader-{N}.yaml               # Basic report written by launch-leader.sh (guaranteed)
├── review-leader-{N}-verdict.yaml       # Verdict written by Review Leader (optional)
├── worker-{N}-{subtask_id}.yaml         # Basic report written by launch-worker.sh (guaranteed)
├── worker-{N}-{subtask_id}-detail.yaml  # Detail written by Worker (optional)
└── processed/                           # Storage for processed reports
```

### Basic report format

```yaml
issue: 42
role: leader    # leader | review-leader
status: completed # completed | failed
exit_code: 0
branch: feat/issue-42
timestamp: "2026-03-02T12:00:00Z"
```

### Leader summary format

```yaml
issue: 42
role: leader
status: completed
branch: "feat/issue-42"
pr: "https://github.com/.../pull/42"
summary: "High-level overview of the implementation"
subtasks_completed: 3
subtasks_total: 3
concerns: null
key_changes:
  - file: "file path"
    what: "description of change"
design_decisions:
  - decision: "what was chosen"
    reason: "rationale"
```

### Review Leader verdict format

```yaml
issue: 42
role: review-leader
complexity: standard
council_members: [worker-reviewer, worker-security]
final_verdict: approve    # approve | fix_required
anti_sycophancy_triggered: false
merged_findings:
  - source: worker-security
    severity: high
    file: src/api/route.ts
    line: 23
    message: "description of the finding"
fix_instructions: null
```

## Next-Action Determination Rules

### For Leader reports

| Report content | queue.yaml update | Next action |
|----------------|-------------------|-------------|
| `status: completed` + summary present | → `review_dispatched` | Launch Review Leader |
| `status: completed` + no summary | → `review_dispatched` | Launch Review Leader (acceptable without summary) |
| `status: failed` | → `error` | Move to next task |

### For Review Leader verdicts

| Verdict | queue.yaml update | Next action |
|---------|-------------------|-------------|
| `final_verdict: approve` | → `ci_checking` | Proceed to **CI check phase** |
| `final_verdict: fix_required` and review_count < 3 | → `fixing` | Restart Leader (fix mode) |
| `final_verdict: fix_required` and review_count >= 3 | → `stuck` | Skip (awaiting user intervention) |

### On Review Leader failure

| State | Response |
|-------|----------|
| `status: failed` + 1st occurrence | Retry once |
| `status: failed` + 2nd occurrence | → `error` |

## Restarting Leader in fix mode

When the Review Leader returns fix_required:

1. Write a fix prompt to: `.claude/tasks/prompts/fix-leader-{N}.md`
2. Include review findings and fix instructions in the fix prompt
3. Restart with `launch-leader.sh leader {N} {branch} fix` (reuses existing worktree)

Fix prompt content:
```markdown
You are a Leader agent. Fix the review findings for Issue #{N}.

## Review Findings
{contents of review-leader-{N}-verdict.yaml}

## Fix Instructions
{contents of fix_instructions}

## Procedure
1. Review the findings
2. Launch Workers to perform the fixes
3. After fixes are complete, write the summary
4. Signal queen-wake
```

## CI Check Phase

After the Review Leader approves, verify that CI passes before marking as done.

### CI check procedure

1. **Check CI status**:

```bash
gh pr checks {PR_number} 2>&1
```

2. **Determination**:

| CI result | queue.yaml update | Next action |
|-----------|-------------------|-------------|
| All checks pass | → `done` | Move to next task |
| Still running/pending | Wait 5 minutes and recheck (up to 3 times) | |
| Failure present | → `ci_fixing` | Restart Leader in fix mode |

3. **Launching CI fix** (on failure):

On CI failure, restart the Leader in fix mode. Include the CI failure log in the fix prompt:

```markdown
You are a Leader agent. Fix the CI failures on branch '{branch}'.

## CI Failure Details
{output of gh pr checks}

## Fix Instructions
Launch Workers to fix the CI errors.
```

4. **Recheck after CI fix**:

After Leader completion, check `gh pr checks` again.
- pass → `done`
- fail (ci_fix_count < 3) → Restart Leader in fix mode again
- fail (ci_fix_count >= 3) → `stuck`

### CI wait loop

```bash
MAX_WAIT=3
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  sleep 300  # Wait 5 minutes
  CI_STATUS=$(gh pr checks {PR_number} 2>&1)
  if echo "$CI_STATUS" | grep -q "fail"; then
    break  # CI failure → proceed to fix phase
  elif echo "$CI_STATUS" | grep -qE "pass|✓" && ! echo "$CI_STATUS" | grep -qE "pending|running|skipping"; then
    break  # All checks pass → proceed to done
  fi
  WAIT_COUNT=$((WAIT_COUNT + 1))
done
```

### After report processing

Move processed reports to `processed/` to prevent reprocessing:

```bash
mv .claude/tasks/reports/leader-{N}.yaml .claude/tasks/reports/processed/
mv .claude/tasks/reports/leader-{N}-summary.yaml .claude/tasks/reports/processed/ 2>/dev/null
mv .claude/tasks/reports/review-leader-{N}*.yaml .claude/tasks/reports/processed/ 2>/dev/null
mv .claude/tasks/reports/worker-{N}-*.yaml .claude/tasks/reports/processed/ 2>/dev/null
```

## Cleanup

Resources have different lifecycles. Clean up each at the right time.

### tmux windows — on task completion

After task reaches done, stuck, or error, kill the tmux windows:

```bash
tmux kill-window -t qb:issue-{N} 2>/dev/null || true
tmux kill-window -t qb:review-{N} 2>/dev/null || true
```

### Worktrees and branches — after PR merge

Worktrees and branches **must be kept alive** until the PR is merged. The Leader's job ends at PR creation; the branch is still needed for review cycles and CI.

Clean up only after confirming the PR is merged:

```bash
# Check if PR is merged
PR_STATE=$(gh pr view {PR_number} --json state -q '.state' 2>/dev/null)
if [ "$PR_STATE" = "MERGED" ]; then
  REPO_DIR=$(git rev-parse --show-toplevel)
  WORKTREE_PATH="$REPO_DIR/.claude/worktrees/{branch}"

  # 1. Remove worktree
  git -C "$REPO_DIR" worktree remove --force "$WORKTREE_PATH" 2>/dev/null || true

  # 2. Delete branch
  git branch -D {branch} 2>/dev/null || true

  # 3. Prune stale references
  git worktree prune
fi
```

### Session-end cleanup

When the Queen session ends (`tmux kill-session -t qb`), prune any stale worktree references:

```bash
git worktree prune
```
