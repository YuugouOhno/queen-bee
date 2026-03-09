#!/bin/bash
# launch-worker.sh - Launch Worker in a tmux split-pane (within Leader's window)
# Usage: launch-worker.sh <role> <issue> <subtask_id> <branch>
#
# Part of beeops: 3-layer multi-agent system (Queen → Leader → Worker)
#
# Features:
# - tmux split-window -h: adds pane within Leader's window
# - No worktree creation (shares Leader's worktree)
# - Signals leader-{issue}-wake on completion
# - Smaller max_turns (15-30)

set -euo pipefail

ROLE="$1"
ISSUE="$2"
SUBTASK_ID="$3"
BRANCH="$4"
SESSION="bo"
REPO_DIR="$(git rev-parse --show-toplevel)"
REPORTS_DIR="$REPO_DIR/.claude/tasks/reports"
PROMPTS_DIR="$REPO_DIR/.claude/tasks/prompts"

mkdir -p "$REPORTS_DIR/processed" "$PROMPTS_DIR"

# ── Role configuration ──
case "$ROLE" in
  worker-coder)
    ROLE_SHORT="worker-coder"
    ENV_VAR="BO_WORKER_CODER"
    WINDOW_NAME="issue-${ISSUE}"
    BORDER_FG="green"
    ROLE_ICON="⚡"
    MAX_TURNS=30
    ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep,Skill"
    ;;
  worker-tester)
    ROLE_SHORT="worker-tester"
    ENV_VAR="BO_WORKER_TESTER"
    WINDOW_NAME="issue-${ISSUE}"
    BORDER_FG="cyan"
    ROLE_ICON="🧪"
    MAX_TURNS=30
    ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep,Skill"
    ;;
  worker-code-reviewer)
    ROLE_SHORT="worker-code-reviewer"
    ENV_VAR="BO_WORKER_CODE_REVIEWER"
    WINDOW_NAME="review-${ISSUE}"
    BORDER_FG="blue"
    ROLE_ICON="🔍"
    MAX_TURNS=15
    ALLOWED_TOOLS="Read,Grep,Glob,Bash,Skill"
    ;;
  worker-security)
    ROLE_SHORT="worker-security"
    ENV_VAR="BO_WORKER_SECURITY"
    WINDOW_NAME="review-${ISSUE}"
    BORDER_FG="red"
    ROLE_ICON="🛡"
    MAX_TURNS=15
    ALLOWED_TOOLS="Read,Grep,Glob,Bash,Skill"
    ;;
  worker-test-auditor)
    ROLE_SHORT="worker-test-auditor"
    ENV_VAR="BO_WORKER_TEST_AUDITOR"
    WINDOW_NAME="review-${ISSUE}"
    BORDER_FG="yellow"
    ROLE_ICON="🧪"
    MAX_TURNS=15
    ALLOWED_TOOLS="Read,Grep,Glob,Bash,Skill"
    ;;
  *)
    echo "Unknown role: $ROLE (expected: worker-coder | worker-tester | worker-code-reviewer | worker-security | worker-test-auditor)" >&2
    exit 1
    ;;
esac

PANE_TITLE="${ROLE_ICON} ${ROLE_SHORT}-${ISSUE}-${SUBTASK_ID}"
SIGNAL_NAME="leader-${ISSUE}-wake"

# ── Determine work directory (use Leader's worktree if available) ──
WORKTREE_PATH="$REPO_DIR/.claude/worktrees/$BRANCH"
if [ -d "$WORKTREE_PATH" ]; then
  WORK_DIR="$WORKTREE_PATH"
else
  WORK_DIR="$REPO_DIR"
fi

# ── Read prompt file (Leader writes this before launching worker) ──
PROMPT_FILE="$PROMPTS_DIR/worker-${ISSUE}-${SUBTASK_ID}.md"
if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

# ── Wrapper script (runs inside tmux pane) ──
WRAPPER="/tmp/agent-wrapper-${ROLE_SHORT}-${ISSUE}-${SUBTASK_ID}.sh"
cat > "$WRAPPER" <<'WRAPPER_HEADER'
#!/bin/bash
set -uo pipefail
WRAPPER_HEADER

cat >> "$WRAPPER" <<WRAPPER_BODY
WORK_DIR="${WORK_DIR}"
REPO_DIR="${REPO_DIR}"
REPORTS_DIR="${REPORTS_DIR}"
PROMPT_FILE="${PROMPT_FILE}"
ROLE="${ROLE}"
ROLE_SHORT="${ROLE_SHORT}"
ENV_VAR="${ENV_VAR}"
ISSUE="${ISSUE}"
SUBTASK_ID="${SUBTASK_ID}"
BRANCH="${BRANCH}"
SIGNAL_NAME="${SIGNAL_NAME}"
MAX_TURNS="${MAX_TURNS}"
ALLOWED_TOOLS="${ALLOWED_TOOLS}"
BO_SCRIPTS_DIR="${BO_SCRIPTS_DIR:-}"
BO_CONTEXTS_DIR="${BO_CONTEXTS_DIR:-}"

cd "\$WORK_DIR"

# Run agent
unset CLAUDECODE
env \${ENV_VAR}=1 \
  BO_SCRIPTS_DIR="\$BO_SCRIPTS_DIR" \
  BO_CONTEXTS_DIR="\$BO_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$PROMPT_FILE")"
EXIT_CODE=\$?

# Write basic report
TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS=\$([ \$EXIT_CODE -eq 0 ] && echo completed || echo failed)

cat > "\$REPORTS_DIR/worker-\${ISSUE}-\${SUBTASK_ID}.yaml" <<REPORT
issue: \$ISSUE
subtask_id: \$SUBTASK_ID
role: \$ROLE
status: \$STATUS
exit_code: \$EXIT_CODE
branch: \$BRANCH
timestamp: \$TIMESTAMP
REPORT

# Update pane style to indicate completion
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ \${ROLE_SHORT}-\${ISSUE}-\${SUBTASK_ID}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ \${ROLE_SHORT}-\${ISSUE}-\${SUBTASK_ID}" 2>/dev/null || true
else
  tmux select-pane -T "❌ \${ROLE_SHORT}-\${ISSUE}-\${SUBTASK_ID}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ \${ROLE_SHORT}-\${ISSUE}-\${SUBTASK_ID}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal Leader
tmux wait-for -S \$SIGNAL_NAME 2>/dev/null || true

echo "--- \$ROLE (subtask \$SUBTASK_ID) completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

chmod +x "$WRAPPER"

# ── Clean up dead panes from previous runs ──
for DEAD_PANE in $(tmux list-panes -t "$SESSION:$WINDOW_NAME" -F '#{pane_index} #{pane_dead}' 2>/dev/null | awk '$2=="1"{print $1}' | sort -rn); do
  tmux kill-pane -t "$SESSION:$WINDOW_NAME.${DEAD_PANE}" 2>/dev/null || true
done

# ── Launch in tmux split-pane (within Leader's window) ──
tmux split-window -h -t "$SESSION:$WINDOW_NAME" "bash '$WRAPPER'; exit 0"

# Pane title + styling
LAST_PANE=$(tmux list-panes -t "$SESSION:$WINDOW_NAME" -F '#{pane_index}' | tail -1)
tmux select-pane -t "$SESSION:$WINDOW_NAME.${LAST_PANE}" -T "$PANE_TITLE"
tmux set-option -p -t "$SESSION:$WINDOW_NAME.${LAST_PANE}" @agent_label "$PANE_TITLE" 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.${LAST_PANE}" allow-rename off 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.${LAST_PANE}" remain-on-exit on 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.${LAST_PANE}" pane-border-style "fg=${BORDER_FG}" 2>/dev/null || true
tmux select-layout -t "$SESSION:$WINDOW_NAME" tiled 2>/dev/null || true

echo "launched:${ROLE_SHORT}-${ISSUE}-${SUBTASK_ID} (window: ${WINDOW_NAME})"
