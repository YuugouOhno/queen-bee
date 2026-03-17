---
name: bo-leader-dispatch
description: Launch Workers in tmux panes, wait for completion, and evaluate quality. Shared dispatch skill for Leader and Review Leader.
---

# bo-leader-dispatch: Worker launch + completion wait + quality evaluation

Operational skill for Leaders and Review Leaders to delegate subtasks to Workers.
Provides Worker visualization via tmux split-pane, event-driven completion waiting, and retry determination based on quality evaluation.

## Prerequisite: Prepare the prompt file

Before launching a Worker, the Leader/Review Leader must write out a prompt file.

Path: `.claude/tasks/prompts/worker-{issue}-{subtask_id}.md`

If the prompt file does not exist, `launch-worker.sh` will exit with an error.

## Launching Workers

### Basic syntax

```bash
bash $BO_SCRIPTS_DIR/launch-worker.sh {role} {issue} {subtask_id} {branch}
```

### Available roles

| Role | Purpose | Launched by |
|------|---------|-------------|
| worker-coder | Code implementation | Leader |
| worker-tester | Test creation | Leader |
| worker-code-reviewer | Code review | Review Leader |
| worker-security | Security review | Review Leader |
| worker-test-auditor | Test audit | Review Leader |

### Launch examples

```bash
# Launch 2 implementation Workers in parallel
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 impl-1 feat/issue-42
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 impl-2 feat/issue-42

# Test Worker
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-tester 42 test-1 feat/issue-42

# Launch Review Workers in parallel
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-code-reviewer 42 review-code feat/issue-42
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-security 42 review-sec feat/issue-42
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-test-auditor 42 review-test feat/issue-42
```

`launch-worker.sh` automatically performs the following:
- **Splits a pane** within the Leader's window (`tmux split-window -h`)
- Evenly arranges all panes with `tmux select-layout tiled`
- Launches `claude --dangerously-skip-permissions --no-session-persistence` with appropriate environment variables and tool restrictions
- Workers share the Leader's worktree (no new worktree is created)
- On completion, writes a report YAML and sends a `tmux wait-for -S leader-{issue}-wake` signal

## Completion Waiting (Event-Driven)

### Blocking wait (until all Workers complete)

```bash
EXPECTED=2  # Set to 1, 2, or 3 based on the number of launched Workers
RECEIVED=0
while [ $RECEIVED -lt $EXPECTED ]; do
  (sleep 600 && tmux wait-for -S leader-{issue}-wake) &
  TIMER_PID=$!
  tmux wait-for leader-{issue}-wake
  kill $TIMER_PID 2>/dev/null
  RECEIVED=$((RECEIVED + 1))
done
```

- All Workers use the same `leader-{issue}-wake` signal, so a counter detects when all have completed
- The counter increments by 1 each time a Worker completes
- The 10-minute timeout applies per Worker (not for the entire group)

### Post-wake determination

Check `.claude/tasks/reports/`:
- **New report found** — Normal completion. Proceed to quality evaluation.
- **No report (timeout)** — Check pane state.

### State check on timeout

```bash
tmux list-panes -t bo:{window_name} -F '#{@agent_label} #{pane_current_command}' 2>/dev/null
```

| State | Meaning | Action |
|-------|---------|--------|
| `claude` is running | Work still in progress | Proceed to next wait-for |
| Returned to `zsh`/`bash` | Completed but signal failed | Check report manually |
| Pane has disappeared | Abnormal termination | Record in concerns |

## Report Files

```
.claude/tasks/reports/
├── worker-{N}-{subtask_id}.yaml         # Basic report written by launch-worker.sh (guaranteed)
└── worker-{N}-{subtask_id}-detail.yaml  # Detail written by Worker (optional)
```

### Basic report format

```yaml
issue: 42
subtask_id: impl-1
role: worker-coder
status: completed  # completed | failed
exit_code: 0
branch: feat/issue-42
timestamp: "2026-03-02T12:00:00Z"
```

## Quality Evaluation Rules

Read Worker reports and evaluate quality:

### Evaluation flow

1. Read the basic report (`worker-{N}-{subtask_id}.yaml`)
2. Read the detail report (`worker-{N}-{subtask_id}-detail.yaml`) if it exists
3. Determine based on the following rules:

| Condition | Verdict | Action |
|-----------|---------|--------|
| `exit_code != 0` | NG | Restart (up to 2 times) |
| No detail report + exit_code == 0 | Warning | Record in concerns, continue |
| Detail report does not cover required content | NG | Restart (up to 2 times) |
| Still failing after 2 restarts | Give up | Record in concerns and continue |
| `exit_code == 0` and content is sufficient | OK | Proceed to next subtask |

### Restart procedure

1. Modify the original prompt file (append previous failure information)
2. Relaunch with the same `launch-worker.sh` command
3. Wait again

```markdown
# Append previous execution results
## Previous Failure
- exit_code: {code}
- Problem: {description of the problem}

## Fix Instructions
{what needs to be fixed}
```

## Subtask Group Execution Patterns

### Parallel execution (independent subtasks)

Launch subtasks that do not depend on each other simultaneously:

```bash
# Write prompt files first
# Write worker-42-impl-api.md
# Write worker-42-impl-ui.md

# Launch in parallel
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 impl-api feat/issue-42
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 impl-ui feat/issue-42

# Wait for 2 Workers
EXPECTED=2
RECEIVED=0
while [ $RECEIVED -lt $EXPECTED ]; do
  (sleep 600 && tmux wait-for -S leader-42-wake) &
  TIMER_PID=$!
  tmux wait-for leader-42-wake
  kill $TIMER_PID 2>/dev/null
  RECEIVED=$((RECEIVED + 1))
done

# Read both reports and evaluate quality
```

### Sequential execution (dependent subtasks)

When a subtask depends on the output of a previous one:

```bash
# Phase 1: Implementation
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 impl-1 feat/issue-42
# Wait + quality evaluation

# Phase 2: Tests (after implementation)
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-tester 42 test-1 feat/issue-42
# Wait + quality evaluation

# Phase 3: PR creation (after all complete)
bash $BO_SCRIPTS_DIR/launch-worker.sh worker-coder 42 pr feat/issue-42
# Wait + quality evaluation
```

### Mixed pattern

```
Phase 1: [worker-coder:impl-api, worker-coder:impl-ui]  ← parallel
Phase 2: [worker-tester:test-1]                          ← sequential
Phase 3: [worker-coder:pr]                               ← sequential
```

## Important Notes

- Workers share the Leader's worktree, so do not launch Workers in parallel if they edit the same files
- Review Workers are read-only and safe to launch in parallel
- subtask_id can be any string, but must be unique within the same issue (no duplicates allowed)
