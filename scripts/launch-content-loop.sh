#!/bin/bash
# launch-content-loop.sh - Creator ↔ Reviewer content quality loop
# Usage: launch-content-loop.sh <task_id> <task_dir> <threshold> <max_loops> [count]
#
# Part of beeops: content creation system (bee-content)
#
# Features:
# - COUNT=1 (default): single content mode — backward compatible
#   Loops: Creator writes content.md → Reviewer audits → score check → repeat
# - COUNT>=2: batch mode
#   Loops: Creator writes N files → Reviewer scores each → approved/rejected sorting → repeat
# - tmux split-window -h for Creator (green) and Reviewer (blue) panes
# - Signals: content-{task_id}-creator-done, content-{task_id}-reviewer-done
# - Exits when score >= threshold (COUNT=1) or approved_count >= count (COUNT>=2) or max_loops reached

set -euo pipefail

TASK_ID="$1"
TASK_DIR="$2"
THRESHOLD="$3"
MAX_LOOPS="$4"
COUNT="${5:-1}"
SESSION="bee-content"
WINDOW_NAME="content-${TASK_ID}"

CREATOR_SIGNAL="content-${TASK_ID}-creator-done"
REVIEWER_SIGNAL="content-${TASK_ID}-reviewer-done"

AGENT_TIMEOUT=3600

log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "${TASK_DIR}/loop.log"
}

log "=== bee-content loop started ==="
log "task_id: ${TASK_ID}"
log "task_dir: ${TASK_DIR}"
log "threshold: ${THRESHOLD}"
log "max_loops: ${MAX_LOOPS}"
log "count: ${COUNT}"

mkdir -p "${TASK_DIR}/prompts"

# ══════════════════════════════════════════════════
# COUNT=1: SINGLE MODE (backward compatible)
# ══════════════════════════════════════════════════

if [ "${COUNT}" -eq 1 ] 2>/dev/null; then

BEST_SCORE=0
BEST_LOOP=0

for LOOP in $(seq 1 "${MAX_LOOPS}"); do
  log "--- Loop ${LOOP}/${MAX_LOOPS} ---"

  # ── Cleanup old panes (keep pane 0 = orchestrator) ──
  for DEAD_PANE in $(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' 2>/dev/null | awk 'NR>1' | sort -rn); do
    tmux kill-pane -t "${SESSION}:${WINDOW_NAME}.${DEAD_PANE}" 2>/dev/null || true
  done

  # ── Read instruction and criteria ──
  INSTRUCTION="$(cat "${TASK_DIR}/instruction.txt")"
  CRITERIA="$(cat "${TASK_DIR}/criteria.txt")"

  # ── Read previous feedback if revision loop ──
  FEEDBACK_SECTION=""
  if [ "${LOOP}" -gt 1 ] && [ -f "${TASK_DIR}/review.yaml" ]; then
    PREV_SCORE=$(grep "^score:" "${TASK_DIR}/review.yaml" | awk '{print $2}' | head -1)
    PREV_FEEDBACK=$(grep -A1000 "^feedback:" "${TASK_DIR}/review.yaml" 2>/dev/null | tail -n +2 | sed 's/^  //' || echo "")
    FEEDBACK_SECTION="## Previous Review (Loop $((LOOP - 1)))
Reviewer score: ${PREV_SCORE}/100
Feedback to address:
${PREV_FEEDBACK}

Address each feedback point explicitly in this revision."
  fi

  # ── Write Creator prompt ──
  CREATOR_PROMPT="${TASK_DIR}/prompts/creator-${LOOP}.md"
  cat > "${CREATOR_PROMPT}" <<CREATOR_PROMPT_EOF
You are a Content Creator agent (bee-content loop ${LOOP}/${MAX_LOOPS}).

## Task
${INSTRUCTION}

## Quality Criteria
${CRITERIA}

${FEEDBACK_SECTION}

## Your Output
1. Write the content to: ${TASK_DIR}/content.md
2. Self-score your work and write to: ${TASK_DIR}/result.yaml

result.yaml format:
\`\`\`yaml
score: <0-100>
reasoning: <brief explanation of why you gave this score>
\`\`\`

3. Signal completion:
\`\`\`bash
tmux wait-for -S ${CREATOR_SIGNAL}
\`\`\`

## Rules
- Do not ask any questions. Write the content now.
- Be creative, thorough, and substantive.
- Address ALL criteria listed above.
- If this is a revision, explicitly address each feedback point.
- Score honestly: do not inflate. The reviewer will score independently.
CREATOR_PROMPT_EOF

  # ── Write Creator wrapper ──
  CREATOR_WRAPPER="/tmp/bee-content-creator-${TASK_ID}-${LOOP}.sh"
  cat > "${CREATOR_WRAPPER}" <<'WRAPPER_HEADER'
#!/bin/bash
set -uo pipefail
WRAPPER_HEADER

  cat >> "${CREATOR_WRAPPER}" <<WRAPPER_BODY
TASK_DIR="${TASK_DIR}"
TASK_ID="${TASK_ID}"
LOOP="${LOOP}"
CREATOR_SIGNAL="${CREATOR_SIGNAL}"
CREATOR_PROMPT="${CREATOR_PROMPT}"
MAX_TURNS=30
ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep"
BO_SCRIPTS_DIR="${BO_SCRIPTS_DIR:-}"
BO_CONTEXTS_DIR="${BO_CONTEXTS_DIR:-}"

# Run Creator agent
unset CLAUDECODE
env BO_CONTENT_CREATOR=1 \
  BO_SCRIPTS_DIR="\$BO_SCRIPTS_DIR" \
  BO_CONTEXTS_DIR="\$BO_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --permission-mode bypassPermissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$CREATOR_PROMPT")"
EXIT_CODE=\$?

# Update pane title
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ creator-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ creator-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
else
  tmux select-pane -T "❌ creator-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ creator-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal loop
tmux wait-for -S \$CREATOR_SIGNAL 2>/dev/null || true

echo "--- creator loop ${LOOP} completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

  chmod +x "${CREATOR_WRAPPER}"

  # ── Launch Creator pane ──
  tmux split-window -h -t "${SESSION}:${WINDOW_NAME}" "bash '${CREATOR_WRAPPER}'; exit 0"
  CREATOR_PANE=$(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' | tail -1)
  tmux select-pane -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" -T "✍️ creator-${TASK_ID}-loop${LOOP}"
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" @agent_label "✍️ creator-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" allow-rename off 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" remain-on-exit on 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" pane-border-style "fg=green" 2>/dev/null || true
  tmux select-layout -t "${SESSION}:${WINDOW_NAME}" tiled 2>/dev/null || true

  log "Creator launched (loop ${LOOP}), waiting for signal..."

  # ── Wait for Creator ──
  (sleep "${AGENT_TIMEOUT}" && tmux wait-for -S "${CREATOR_SIGNAL}") &
  TIMER_PID=$!
  tmux wait-for "${CREATOR_SIGNAL}"
  kill "$TIMER_PID" 2>/dev/null || true
  # ── Read Creator score ──
  CREATOR_SCORE=0
  if [ -f "${TASK_DIR}/result.yaml" ]; then
    CREATOR_SCORE=$(grep "^score:" "${TASK_DIR}/result.yaml" | awk '{print $2}' | head -1)
    CREATOR_SCORE="${CREATOR_SCORE:-0}"
  fi
  log "Creator self-score: ${CREATOR_SCORE}/100"

  # ── Cleanup Creator pane, keep pane 0 ──
  for DEAD_PANE in $(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' 2>/dev/null | awk 'NR>1' | sort -rn); do
    tmux kill-pane -t "${SESSION}:${WINDOW_NAME}.${DEAD_PANE}" 2>/dev/null || true
  done

  # ── Write Reviewer prompt ──
  REVIEWER_PROMPT="${TASK_DIR}/prompts/reviewer-${LOOP}.md"
  cat > "${REVIEWER_PROMPT}" <<REVIEWER_PROMPT_EOF
You are a Content Reviewer agent (bee-content loop ${LOOP}/${MAX_LOOPS}).

## Original Task Instruction
${INSTRUCTION}

## Quality Criteria
${CRITERIA}

## Your Task
1. Read the content: ${TASK_DIR}/content.md
2. Evaluate independently against the criteria above.
3. Write your audit to: ${TASK_DIR}/review.yaml

review.yaml format:
\`\`\`yaml
score: <0-100>
verdict: approved  # approved | needs_improvement
feedback: |
  1. <specific issue or praise>
  2. <specific issue or praise>
  3. ...
\`\`\`

Use verdict "approved" only if score >= ${THRESHOLD}.

4. Signal completion:
\`\`\`bash
tmux wait-for -S ${REVIEWER_SIGNAL}
\`\`\`

## Anti-Sycophancy Rules
- Do NOT anchor to the creator's self-score.
- Score based solely on the content quality and the criteria.
- Cite specific problems with specific evidence.
- Do not give vague praise like "well-written" without backing.
- If criteria are not met, say so clearly.
REVIEWER_PROMPT_EOF

  # ── Write Reviewer wrapper ──
  REVIEWER_WRAPPER="/tmp/bee-content-reviewer-${TASK_ID}-${LOOP}.sh"
  cat > "${REVIEWER_WRAPPER}" <<'WRAPPER_HEADER'
#!/bin/bash
set -uo pipefail
WRAPPER_HEADER

  cat >> "${REVIEWER_WRAPPER}" <<WRAPPER_BODY
TASK_DIR="${TASK_DIR}"
TASK_ID="${TASK_ID}"
LOOP="${LOOP}"
REVIEWER_SIGNAL="${REVIEWER_SIGNAL}"
REVIEWER_PROMPT="${REVIEWER_PROMPT}"
MAX_TURNS=20
ALLOWED_TOOLS="Read,Bash,Glob,Grep"
BO_SCRIPTS_DIR="${BO_SCRIPTS_DIR:-}"
BO_CONTEXTS_DIR="${BO_CONTEXTS_DIR:-}"

# Run Reviewer agent
unset CLAUDECODE
env BO_CONTENT_REVIEWER=1 \
  BO_SCRIPTS_DIR="\$BO_SCRIPTS_DIR" \
  BO_CONTEXTS_DIR="\$BO_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --permission-mode bypassPermissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$REVIEWER_PROMPT")"
EXIT_CODE=\$?

# Update pane title
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ reviewer-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ reviewer-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
else
  tmux select-pane -T "❌ reviewer-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ reviewer-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal loop
tmux wait-for -S \$REVIEWER_SIGNAL 2>/dev/null || true

echo "--- reviewer loop ${LOOP} completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

  chmod +x "${REVIEWER_WRAPPER}"

  # ── Launch Reviewer pane ──
  tmux split-window -h -t "${SESSION}:${WINDOW_NAME}" "bash '${REVIEWER_WRAPPER}'; exit 0"
  REVIEWER_PANE=$(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' | tail -1)
  tmux select-pane -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" -T "🔍 reviewer-${TASK_ID}-loop${LOOP}"
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" @agent_label "🔍 reviewer-${TASK_ID}-loop${LOOP}" 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" allow-rename off 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" remain-on-exit on 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" pane-border-style "fg=blue" 2>/dev/null || true
  tmux select-layout -t "${SESSION}:${WINDOW_NAME}" tiled 2>/dev/null || true

  log "Reviewer launched (loop ${LOOP}), waiting for signal..."

  # ── Wait for Reviewer ──
  (sleep "${AGENT_TIMEOUT}" && tmux wait-for -S "${REVIEWER_SIGNAL}") &
  TIMER_PID=$!
  tmux wait-for "${REVIEWER_SIGNAL}"
  kill "$TIMER_PID" 2>/dev/null || true

  # ── Read Reviewer score ──
  REVIEWER_SCORE=0
  REVIEWER_VERDICT="needs_improvement"
  if [ -f "${TASK_DIR}/review.yaml" ]; then
    REVIEWER_SCORE=$(grep "^score:" "${TASK_DIR}/review.yaml" | awk '{print $2}' | head -1)
    REVIEWER_SCORE="${REVIEWER_SCORE:-0}"
    REVIEWER_VERDICT=$(grep "^verdict:" "${TASK_DIR}/review.yaml" | awk '{print $2}' | head -1)
    REVIEWER_VERDICT="${REVIEWER_VERDICT:-needs_improvement}"
  fi
  log "Reviewer score: ${REVIEWER_SCORE}/100 | verdict: ${REVIEWER_VERDICT}"

  # ── Track best score ──
  if [ "${REVIEWER_SCORE}" -ge "${BEST_SCORE}" ] 2>/dev/null; then
    BEST_SCORE="${REVIEWER_SCORE}"
    BEST_LOOP="${LOOP}"
  fi

  # ── Check threshold ──
  if [ "${REVIEWER_VERDICT}" = "approved" ] || [ "${REVIEWER_SCORE}" -ge "${THRESHOLD}" ] 2>/dev/null; then
    log "=== DONE: score ${REVIEWER_SCORE} >= threshold ${THRESHOLD} (loop ${LOOP}) ==="
    log "Content written to: ${TASK_DIR}/content.md"
    echo ""
    echo "bee-content COMPLETE"
    echo "  loop:      ${LOOP}/${MAX_LOOPS}"
    echo "  score:     ${REVIEWER_SCORE}/100 (threshold: ${THRESHOLD})"
    echo "  verdict:   ${REVIEWER_VERDICT}"
    echo "  output:    ${TASK_DIR}/content.md"
    exit 0
  fi

  log "Score ${REVIEWER_SCORE} < threshold ${THRESHOLD}, continuing..."
done

# ── Max loops reached ──
log "=== MAX LOOPS REACHED: best score ${BEST_SCORE} (loop ${BEST_LOOP}) ==="
echo ""
echo "bee-content FINISHED (max loops reached)"
echo "  best score: ${BEST_SCORE}/100 (loop ${BEST_LOOP}, threshold: ${THRESHOLD})"
echo "  output:     ${TASK_DIR}/content.md"
echo "  review:     ${TASK_DIR}/review.yaml"
exit 0

fi  # end COUNT=1 branch

# ══════════════════════════════════════════════════
# COUNT>=2: BATCH MODE
# ══════════════════════════════════════════════════

log "=== BATCH MODE: target=${COUNT} pieces ==="

mkdir -p "${TASK_DIR}/items/pending" "${TASK_DIR}/items/approved" "${TASK_DIR}/items/rejected"
mkdir -p "${TASK_DIR}/reviews"

# ── state.yaml helpers ──

read_state() {
  APPROVED_COUNT=$(grep "^approved:" "${TASK_DIR}/state.yaml" | awk '{print $2}')
  CURRENT_LOOP=$(grep "^current_loop:" "${TASK_DIR}/state.yaml" | awk '{print $2}')
  APPROVED_COUNT="${APPROVED_COUNT:-0}"
  CURRENT_LOOP="${CURRENT_LOOP:-0}"
}

update_state() {
  awk -v a="$1" -v l="$2" '
    /^approved:/ { print "approved: " a; next }
    /^current_loop:/ { print "current_loop: " l; next }
    { print }
  ' "${TASK_DIR}/state.yaml" > "${TASK_DIR}/state.yaml.tmp" \
  && mv "${TASK_DIR}/state.yaml.tmp" "${TASK_DIR}/state.yaml"
}

# ── Sorting helper ──

parse_and_sort_review() {
  local review_file="$1"
  local loop_num="$2"
  awk -v pending="${TASK_DIR}/items/pending" \
      -v approved_dir="${TASK_DIR}/items/approved" \
      -v rejected_dir="${TASK_DIR}/items/rejected" \
      -v loop="$loop_num" \
      'BEGIN { id=""; score=0; verdict="" }
       /^- id:/ {
         if (id != "") do_move()
         id=$2; gsub(/"/, "", id); score=0; verdict=""
       }
       /^  score:/ { score=$2 }
       /^  verdict:/ { verdict=$2 }
       END { if (id != "") do_move() }
       function do_move() {
         src=pending "/" id ".md"
         if (verdict == "approved") {
           dst=approved_dir "/" id ".md"
         } else {
           dst=rejected_dir "/" id "-score" score "-loop" loop ".md"
         }
         print "mv \"" src "\" \"" dst "\""
       }
      ' "$review_file" | bash 2>/dev/null || true
}

# ── Initialize state.yaml if missing ──
if [ ! -f "${TASK_DIR}/state.yaml" ]; then
  cat > "${TASK_DIR}/state.yaml" <<STATE_EOF
name: ${TASK_ID}
count: ${COUNT}
approved: 0
current_loop: 0
STATE_EOF
fi

read_state

# ── Main batch loop ──
while [ "${APPROVED_COUNT}" -lt "${COUNT}" ] && [ "${CURRENT_LOOP}" -lt "${MAX_LOOPS}" ]; do
  CURRENT_LOOP=$((CURRENT_LOOP + 1))
  NEEDED=$((COUNT - APPROVED_COUNT))

  log "--- Batch Loop ${CURRENT_LOOP}/${MAX_LOOPS}: approved=${APPROVED_COUNT}/${COUNT}, needed=${NEEDED} ---"

  # ── 1. Clear pending/ ──
  rm -f "${TASK_DIR}/items/pending"/*.md 2>/dev/null || true

  # ── 2. Build file list for Creator ──
  PENDING_FILES=""
  for i in $(seq 1 "${NEEDED}"); do
    PENDING_FILES="${PENDING_FILES}${TASK_DIR}/items/pending/loop${CURRENT_LOOP}-${i}.md
"
  done

  # ── Gather examples and feedback ──
  GOOD_EXAMPLES=""
  if ls "${TASK_DIR}/items/approved/"*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    GOOD_EXAMPLES="## Good Examples (already approved)
The following files were approved. Study them to understand what quality is expected, then exceed it:
$(ls "${TASK_DIR}/items/approved/"*.md 2>/dev/null | sed 's/^/- /')"
  fi

  AVOID_EXAMPLES=""
  if ls "${TASK_DIR}/items/rejected/"*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    RECENT_REJECTED=$(ls -1t "${TASK_DIR}/items/rejected/"*.md 2>/dev/null | head -10 | sed 's/^/- /')
    AVOID_EXAMPLES="## Rejected Examples (avoid these failure modes)
The following files were rejected. Do NOT repeat their mistakes:
${RECENT_REJECTED}"
  fi

  PREV_FEEDBACK_SECTION=""
  PREV_REVIEW_FILE="${TASK_DIR}/reviews/review-loop$((CURRENT_LOOP - 1)).yaml"
  if [ "${CURRENT_LOOP}" -gt 1 ] && [ -f "${PREV_REVIEW_FILE}" ]; then
    PREV_FEEDBACK_SECTION="## Feedback from Previous Loop (loop $((CURRENT_LOOP - 1)))
Address the following issues in your new pieces:
$(cat "${PREV_REVIEW_FILE}")"
  fi

  # ── Read instruction and criteria ──
  INSTRUCTION="$(cat "${TASK_DIR}/instruction.txt")"
  CRITERIA="$(cat "${TASK_DIR}/criteria.txt")"

  # ── Write Creator prompt ──
  CREATOR_PROMPT="${TASK_DIR}/prompts/creator-loop${CURRENT_LOOP}.md"
  cat > "${CREATOR_PROMPT}" <<CREATOR_PROMPT_EOF
You are a Content Creator agent (bee-content batch loop ${CURRENT_LOOP}/${MAX_LOOPS}).

## Task
${INSTRUCTION}

## Quality Criteria
${CRITERIA}

${GOOD_EXAMPLES}

${AVOID_EXAMPLES}

${PREV_FEEDBACK_SECTION}

## Your Output
Write ${NEEDED} independent, high-quality piece(s) of content. Each must be complete and standalone.

Write to these exact file paths:
$(echo "${PENDING_FILES}" | sed '/^$/d' | sed 's/^/- /')

Each piece must be meaningfully different — explore different angles, formats, or perspectives.
Do NOT write minor variations of each other.

Self-score your work and write to: ${TASK_DIR}/reviews/result-loop${CURRENT_LOOP}.yaml

result-loop${CURRENT_LOOP}.yaml format:
\`\`\`yaml
- id: "loop${CURRENT_LOOP}-1"
  score: <0-100>
  reasoning: <brief explanation>
- id: "loop${CURRENT_LOOP}-2"
  score: <0-100>
  reasoning: <brief explanation>
\`\`\`

Signal completion:
\`\`\`bash
tmux wait-for -S ${CREATOR_SIGNAL}
\`\`\`

## Rules
- Do not ask any questions. Write the content now.
- Be creative, thorough, and substantive.
- Address ALL criteria for every piece.
- Score honestly: do not inflate. The reviewer will score independently.
CREATOR_PROMPT_EOF

  # ── Write Creator wrapper ──
  CREATOR_WRAPPER="/tmp/bee-content-creator-${TASK_ID}-loop${CURRENT_LOOP}.sh"
  cat > "${CREATOR_WRAPPER}" <<'WRAPPER_HEADER'
#!/bin/bash
set -uo pipefail
WRAPPER_HEADER

  cat >> "${CREATOR_WRAPPER}" <<WRAPPER_BODY
TASK_DIR="${TASK_DIR}"
TASK_ID="${TASK_ID}"
CURRENT_LOOP="${CURRENT_LOOP}"
CREATOR_SIGNAL="${CREATOR_SIGNAL}"
CREATOR_PROMPT="${CREATOR_PROMPT}"
MAX_TURNS=50
ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep"
BO_SCRIPTS_DIR="${BO_SCRIPTS_DIR:-}"
BO_CONTEXTS_DIR="${BO_CONTEXTS_DIR:-}"

# Run Creator agent
unset CLAUDECODE
env BO_CONTENT_CREATOR=1 \
  BO_SCRIPTS_DIR="\$BO_SCRIPTS_DIR" \
  BO_CONTEXTS_DIR="\$BO_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --permission-mode bypassPermissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$CREATOR_PROMPT")"
EXIT_CODE=\$?

# Update pane title
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ creator-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ creator-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
else
  tmux select-pane -T "❌ creator-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ creator-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal loop
tmux wait-for -S \$CREATOR_SIGNAL 2>/dev/null || true

echo "--- creator batch loop ${CURRENT_LOOP} completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

  chmod +x "${CREATOR_WRAPPER}"

  # ── Launch Creator pane ──
  tmux split-window -h -t "${SESSION}:${WINDOW_NAME}" "bash '${CREATOR_WRAPPER}'; exit 0"
  CREATOR_PANE=$(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' | tail -1)
  tmux select-pane -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" -T "✍️ creator-${TASK_ID}-loop${CURRENT_LOOP}"
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" @agent_label "✍️ creator-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" allow-rename off 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" remain-on-exit on 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${CREATOR_PANE}" pane-border-style "fg=green" 2>/dev/null || true
  tmux select-layout -t "${SESSION}:${WINDOW_NAME}" tiled 2>/dev/null || true

  log "Creator launched (batch loop ${CURRENT_LOOP}), waiting for signal..."

  # ── 4. Wait for Creator ──
  (sleep "${AGENT_TIMEOUT}" && tmux wait-for -S "${CREATOR_SIGNAL}") &
  TIMER_PID=$!
  tmux wait-for "${CREATOR_SIGNAL}"
  kill "$TIMER_PID" 2>/dev/null || true

  # ── Cleanup Creator pane ──
  for DEAD_PANE in $(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' 2>/dev/null | awk 'NR>1' | sort -rn); do
    tmux kill-pane -t "${SESSION}:${WINDOW_NAME}.${DEAD_PANE}" 2>/dev/null || true
  done

  # ── 5. Write Reviewer prompt ──
  REVIEWER_PROMPT="${TASK_DIR}/prompts/reviewer-loop${CURRENT_LOOP}.md"
  PENDING_LIST=$(ls "${TASK_DIR}/items/pending/"*.md 2>/dev/null | sed 's/^/- /' || echo "(no files found)")
  cat > "${REVIEWER_PROMPT}" <<REVIEWER_PROMPT_EOF
You are a Content Reviewer agent (bee-content batch loop ${CURRENT_LOOP}/${MAX_LOOPS}).

## Original Task Instruction
${INSTRUCTION}

## Quality Criteria
${CRITERIA}

## Your Task
Evaluate each of the following content files independently:
${PENDING_LIST}

For each file:
1. Read the file
2. Score it independently against the criteria (0-100)
3. Assign verdict: "approved" only if score >= ${THRESHOLD}, otherwise "needs_improvement"
4. Write specific feedback

Write your results to: ${TASK_DIR}/reviews/review-loop${CURRENT_LOOP}.yaml

review-loop${CURRENT_LOOP}.yaml format:
\`\`\`yaml
- id: "loop${CURRENT_LOOP}-1"
  score: <0-100>
  verdict: approved  # approved | needs_improvement
  feedback: |
    1. <specific finding>
    2. <specific finding>
    3. <specific finding>
- id: "loop${CURRENT_LOOP}-2"
  score: <0-100>
  verdict: approved  # approved | needs_improvement
  feedback: |
    1. <specific finding>
    2. <specific finding>
\`\`\`

The id must match the filename stem (e.g., file loop${CURRENT_LOOP}-1.md → id "loop${CURRENT_LOOP}-1").

Signal completion:
\`\`\`bash
tmux wait-for -S ${REVIEWER_SIGNAL}
\`\`\`

## Anti-Sycophancy Rules
- Score each file independently. Do NOT compare pieces to each other.
- Apply the threshold consistently. Do not be lenient just because many are pending.
- Cite specific problems with specific evidence.
- Even approved pieces deserve specific feedback for further improvement.
- verdict "approved" only if score >= ${THRESHOLD}.
REVIEWER_PROMPT_EOF

  # ── 6. Write Reviewer wrapper ──
  REVIEWER_WRAPPER="/tmp/bee-content-reviewer-${TASK_ID}-loop${CURRENT_LOOP}.sh"
  cat > "${REVIEWER_WRAPPER}" <<'WRAPPER_HEADER'
#!/bin/bash
set -uo pipefail
WRAPPER_HEADER

  cat >> "${REVIEWER_WRAPPER}" <<WRAPPER_BODY
TASK_DIR="${TASK_DIR}"
TASK_ID="${TASK_ID}"
CURRENT_LOOP="${CURRENT_LOOP}"
REVIEWER_SIGNAL="${REVIEWER_SIGNAL}"
REVIEWER_PROMPT="${REVIEWER_PROMPT}"
MAX_TURNS=30
ALLOWED_TOOLS="Read,Bash,Glob,Grep"
BO_SCRIPTS_DIR="${BO_SCRIPTS_DIR:-}"
BO_CONTEXTS_DIR="${BO_CONTEXTS_DIR:-}"

# Run Reviewer agent
unset CLAUDECODE
env BO_CONTENT_REVIEWER=1 \
  BO_SCRIPTS_DIR="\$BO_SCRIPTS_DIR" \
  BO_CONTEXTS_DIR="\$BO_CONTEXTS_DIR" \
  claude --dangerously-skip-permissions \
  --permission-mode bypassPermissions \
  --allowedTools "\$ALLOWED_TOOLS" \
  --max-turns \$MAX_TURNS \
  "\$(cat "\$REVIEWER_PROMPT")"
EXIT_CODE=\$?

# Update pane title
if [ \$EXIT_CODE -eq 0 ]; then
  tmux select-pane -T "✅ reviewer-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "✅ reviewer-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
else
  tmux select-pane -T "❌ reviewer-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p @agent_label "❌ reviewer-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
fi
tmux set-option -p pane-border-style "fg=colour240" 2>/dev/null || true

# Signal loop
tmux wait-for -S \$REVIEWER_SIGNAL 2>/dev/null || true

echo "--- reviewer batch loop ${CURRENT_LOOP} completed (exit=\$EXIT_CODE) ---"
WRAPPER_BODY

  chmod +x "${REVIEWER_WRAPPER}"

  # ── Launch Reviewer pane ──
  tmux split-window -h -t "${SESSION}:${WINDOW_NAME}" "bash '${REVIEWER_WRAPPER}'; exit 0"
  REVIEWER_PANE=$(tmux list-panes -t "${SESSION}:${WINDOW_NAME}" -F '#{pane_index}' | tail -1)
  tmux select-pane -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" -T "🔍 reviewer-${TASK_ID}-loop${CURRENT_LOOP}"
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" @agent_label "🔍 reviewer-${TASK_ID}-loop${CURRENT_LOOP}" 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" allow-rename off 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" remain-on-exit on 2>/dev/null || true
  tmux set-option -p -t "${SESSION}:${WINDOW_NAME}.${REVIEWER_PANE}" pane-border-style "fg=blue" 2>/dev/null || true
  tmux select-layout -t "${SESSION}:${WINDOW_NAME}" tiled 2>/dev/null || true

  log "Reviewer launched (batch loop ${CURRENT_LOOP}), waiting for signal..."

  # ── 7. Wait for Reviewer ──
  (sleep "${AGENT_TIMEOUT}" && tmux wait-for -S "${REVIEWER_SIGNAL}") &
  REVIEWER_TIMER_PID=$!
  tmux wait-for "${REVIEWER_SIGNAL}" 2>/dev/null || log "WARNING: Reviewer timed out after ${AGENT_TIMEOUT}s (batch loop ${CURRENT_LOOP})"
  kill "$REVIEWER_TIMER_PID" 2>/dev/null || true

  # ── 8. Sort items based on review ──
  REVIEW_FILE="${TASK_DIR}/reviews/review-loop${CURRENT_LOOP}.yaml"
  if [ -f "${REVIEW_FILE}" ]; then
    log "Sorting items from review-loop${CURRENT_LOOP}.yaml..."
    parse_and_sort_review "${REVIEW_FILE}" "${CURRENT_LOOP}"
  else
    log "WARNING: review-loop${CURRENT_LOOP}.yaml not found, skipping sort"
  fi

  # ── 9. Count approved items ──
  NEW_APPROVED=$(ls "${TASK_DIR}/items/approved/"*.md 2>/dev/null | wc -l | tr -d ' ')
  NEW_APPROVED="${NEW_APPROVED:-0}"

  # ── Update state.yaml ──
  update_state "${NEW_APPROVED}" "${CURRENT_LOOP}"

  # ── 10. Report and continue ──
  log "Loop ${CURRENT_LOOP} done: approved=${NEW_APPROVED}/${COUNT}"
  echo "  Loop ${CURRENT_LOOP}: ${NEW_APPROVED}/${COUNT} approved so far"

  # Refresh state for while condition check
  read_state
done

# ── Final result ──
FINAL_APPROVED=$(ls "${TASK_DIR}/items/approved/"*.md 2>/dev/null | wc -l | tr -d ' ')
FINAL_APPROVED="${FINAL_APPROVED:-0}"

if [ "${FINAL_APPROVED}" -ge "${COUNT}" ]; then
  log "=== BATCH COMPLETE: ${FINAL_APPROVED}/${COUNT} approved ==="
  echo ""
  echo "=== BATCH COMPLETE: ${FINAL_APPROVED}/${COUNT} approved ==="
  echo "Output: ${TASK_DIR}/items/approved/"
else
  log "=== BATCH FINISHED (max loops reached): ${FINAL_APPROVED}/${COUNT} approved ==="
  echo ""
  echo "=== BATCH FINISHED (max loops reached): ${FINAL_APPROVED}/${COUNT} approved ==="
  echo "Output: ${TASK_DIR}/items/approved/"
fi
exit 0
