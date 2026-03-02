#!/bin/bash
# launch-leader.sh - Launch Leader or Review Leader in a tmux window (with git worktree isolation)
# Usage: launch-leader.sh <role> <issue> <branch> [fix]
#
# Part of queen-bee: 3-layer multi-agent system (Queen → Leader → Worker)
#
# Features:
# - tmux new-window: each issue gets its own window (not pane)
# - Git worktree isolation: impl leader gets isolated copy of the repo
# - Review leader works on main repo (read-only)
# - FIX_MODE: reuse existing worktree/branch when called with 'fix'

set -euo pipefail

ROLE="$1"
ISSUE="$2"
BRANCH="$3"
FIX_MODE="${4:-}"
SESSION="qb"
REPO_DIR="$(git rev-parse --show-toplevel)"
REPORTS_DIR="$REPO_DIR/.claude/tasks/reports"
PROMPTS_DIR="$REPO_DIR/.claude/tasks/prompts"
WORKTREES_DIR="$REPO_DIR/.claude/worktrees"

mkdir -p "$REPORTS_DIR/processed" "$PROMPTS_DIR" "$WORKTREES_DIR"

# ── Role configuration ──
case "$ROLE" in
  leader)
    ROLE_SHORT="leader"
    ENV_VAR="QB_LEADER"
    WINDOW_NAME="issue-${ISSUE}"
    BORDER_FG="blue"
    ROLE_ICON="👑"
    MAX_TURNS=80
    ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep,Skill"
    ;;
  review-leader)
    ROLE_SHORT="review-leader"
    ENV_VAR="QB_REVIEW_LEADER"
    WINDOW_NAME="review-${ISSUE}"
    BORDER_FG="magenta"
    ROLE_ICON="🔮"
    MAX_TURNS=40
    ALLOWED_TOOLS="Read,Grep,Glob,Bash,Skill"
    ;;
  *)
    echo "Unknown role: $ROLE (expected: leader | review-leader)" >&2
    exit 1
    ;;
esac

PANE_TITLE="${ROLE_ICON} ${ROLE_SHORT}-${ISSUE}"

# ── Worktree setup (leader only, review-leader uses main repo) ──
WORK_DIR="$REPO_DIR"
WORKTREE_PATH=""

if [ "$ROLE" = "leader" ]; then
  WORKTREE_PATH="$WORKTREES_DIR/$BRANCH"

  if [ "$FIX_MODE" = "fix" ] && [ -d "$WORKTREE_PATH" ]; then
    # FIX_MODE: reuse existing worktree
    WORK_DIR="$WORKTREE_PATH"
  else
    # Clean up stale worktree if exists
    if [ -d "$WORKTREE_PATH" ]; then
      git -C "$REPO_DIR" worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
    fi
    # Create fresh worktree with new branch from main
    git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH" main 2>/dev/null || \
      git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" "$BRANCH" 2>/dev/null || {
        git -C "$REPO_DIR" branch -D "$BRANCH" 2>/dev/null || true
        git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH" main
      }
    WORK_DIR="$WORKTREE_PATH"
    # Symlink node_modules and other untracked but required dirs
    ln -sfn "$REPO_DIR/node_modules" "$WORKTREE_PATH/node_modules" 2>/dev/null || true
    ln -sfn "$REPO_DIR/.next" "$WORKTREE_PATH/.next" 2>/dev/null || true
    # Ensure reports/prompts dirs are accessible from worktree
    mkdir -p "$WORKTREE_PATH/.claude/tasks"
    ln -sfn "$REPORTS_DIR" "$WORKTREE_PATH/.claude/tasks/reports"
    ln -sfn "$PROMPTS_DIR" "$WORKTREE_PATH/.claude/tasks/prompts"
  fi
fi

# ── Write prompt file ──
PROMPT_FILE="$PROMPTS_DIR/${ROLE_SHORT}-${ISSUE}.md"

# Use fix prompt if it exists (written by Queen)
FIX_PROMPT="$PROMPTS_DIR/fix-${ROLE_SHORT}-${ISSUE}.md"
if [ "$FIX_MODE" = "fix" ] && [ -f "$FIX_PROMPT" ]; then
  cp "$FIX_PROMPT" "$PROMPT_FILE"
  rm "$FIX_PROMPT"
else
case "$ROLE" in
  leader)
    cat > "$PROMPT_FILE" <<PROMPT_EOF
You are a Leader agent (queen-bee L2).
You are responsible for completing the implementation of GitHub Issue #${ISSUE}.

## Work Environment
- Working directory: ${WORK_DIR}
- Branch '${BRANCH}' is already checked out (git worktree)
- Report output directory: ${REPORTS_DIR}
- Prompt output directory: ${PROMPTS_DIR}
- Issue number: ${ISSUE}

## Procedure
1. Review the issue: gh issue view ${ISSUE} --json body,title,labels
2. Skill: qb-task-decomposer to decompose into subtasks
3. Skill: qb-leader-dispatch to launch Workers in parallel
4. Evaluate Worker reports for quality (re-run up to 2 times if unsatisfactory)
5. After all subtasks are complete, perform a self-critical review (read the PR diff and verify alignment with Issue requirements)
6. Write ${REPORTS_DIR}/leader-${ISSUE}-summary.yaml
7. Send tmux wait-for -S queen-wake

## Report Format (leader-${ISSUE}-summary.yaml)
\`\`\`yaml
issue: ${ISSUE}
role: leader
status: completed  # completed | failed
branch: ${BRANCH}
pr: "PR URL"
summary: "High-level overview of the implementation"
subtasks_completed: 3
subtasks_total: 3
concerns: null  # Note any concerns if applicable
key_changes:
  - file: "file path"
    what: "description of change"
design_decisions:
  - decision: "what was chosen"
    reason: "why"
\`\`\`

## Critical Rules
- Never ask the user questions. Make all decisions yourself
- Delegate work to Workers. Do not write code yourself
- Have the final worker-coder create the PR
- Handle errors on your own
PROMPT_EOF
    ;;

  review-leader)
    cat > "$PROMPT_FILE" <<PROMPT_EOF
You are a Review Leader agent (queen-bee L2).
You are responsible for reviewing the PR for Issue #${ISSUE}.

## Work Environment
- Working directory: ${WORK_DIR}
- Branch: ${BRANCH}
- Report output directory: ${REPORTS_DIR}
- Prompt output directory: ${PROMPTS_DIR}
- Issue number: ${ISSUE}

## Procedure
1. Review the PR diff: gh pr diff --name-only && gh pr diff
2. Determine complexity (simple/standard/complex)
3. Skill: qb-leader-dispatch to launch Review Workers in parallel
4. Aggregate Worker findings + perform anti-sycophancy check
5. Write ${REPORTS_DIR}/review-leader-${ISSUE}-verdict.yaml
6. Send tmux wait-for -S queen-wake

## Complexity Rules
| Complexity | Criteria | Workers to Launch |
|------------|----------|-------------------|
| simple | Changed files <= 2 and all are config/docs | worker-reviewer only |
| complex | Changed files >= 5, includes auth/migration | worker-reviewer + worker-security + worker-test-auditor |
| standard | Everything else | worker-reviewer + worker-security |

## Report Format (review-leader-${ISSUE}-verdict.yaml)
\`\`\`yaml
issue: ${ISSUE}
role: review-leader
complexity: standard
council_members: [worker-reviewer, worker-security]
final_verdict: approve  # approve | fix_required
anti_sycophancy_triggered: false
merged_findings:
  - source: worker-security
    severity: high
    file: "file path"
    line: line number
    message: "description of finding"
fix_instructions: null  # Only populate when fix_required
\`\`\`

## Critical Rules
- Never ask the user questions. Make all decisions yourself
- Delegate reviews to Review Workers. Do not read code yourself (only grasp the diff overview)
- Only mark fix_required for critical issues
PROMPT_EOF
    ;;
esac
fi  # end of fix prompt check

# ── Wrapper script (runs inside tmux pane) ──
WRAPPER="/tmp/agent-wrapper-${ROLE_SHORT}-${ISSUE}.sh"
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
BRANCH="${BRANCH}"
WORKTREE_PATH="${WORKTREE_PATH}"
MAX_TURNS="${MAX_TURNS}"
ALLOWED_TOOLS="${ALLOWED_TOOLS}"
QB_SCRIPTS_DIR="${QB_SCRIPTS_DIR:-}"
QB_CONTEXTS_DIR="${QB_CONTEXTS_DIR:-}"

cd "\$WORK_DIR"

# Run agent
unset CLAUDECODE
env \${ENV_VAR}=1 \
  QB_SCRIPTS_DIR="\$QB_SCRIPTS_DIR" \
  QB_CONTEXTS_DIR="\$QB_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$PROMPT_FILE")"
EXIT_CODE=\$?

# Write basic report
TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS=\$([ \$EXIT_CODE -eq 0 ] && echo completed || echo failed)

cat > "\$REPORTS_DIR/\${ROLE_SHORT}-\${ISSUE}.yaml" <<REPORT
issue: \$ISSUE
role: \$ROLE
status: \$STATUS
exit_code: \$EXIT_CODE
branch: \$BRANCH
timestamp: \$TIMESTAMP
REPORT

# Update pane style to indicate completion
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ \${ROLE_SHORT}-\${ISSUE}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ \${ROLE_SHORT}-\${ISSUE}" 2>/dev/null || true
else
  tmux select-pane -T "❌ \${ROLE_SHORT}-\${ISSUE}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ \${ROLE_SHORT}-\${ISSUE}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal Queen
tmux wait-for -S queen-wake 2>/dev/null || true

# Note: worktree is intentionally kept alive after Leader completion.
# The branch is needed for PR review cycles and CI checks.
# Cleanup happens after PR merge (managed by Queen via qb-dispatch).

echo "--- \$ROLE completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

chmod +x "$WRAPPER"

# ── Kill existing window with same name if present ──
tmux kill-window -t "$SESSION:$WINDOW_NAME" 2>/dev/null || true

# ── Create new tmux window ──
tmux new-window -t "$SESSION" -n "$WINDOW_NAME" "bash '$WRAPPER'; exit 0"

# Pane title + styling
tmux select-pane -t "$SESSION:$WINDOW_NAME.0" -T "$PANE_TITLE"
tmux set-option -p -t "$SESSION:$WINDOW_NAME.0" @agent_label "$PANE_TITLE" 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.0" allow-rename off 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.0" remain-on-exit on 2>/dev/null || true
tmux set-option -p -t "$SESSION:$WINDOW_NAME.0" pane-border-style "fg=${BORDER_FG}" 2>/dev/null || true

echo "launched:${ROLE_SHORT}-${ISSUE} (window: ${WINDOW_NAME}, worktree: ${WORKTREE_PATH:-none})"
