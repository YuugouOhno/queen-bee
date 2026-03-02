Launch a Queen session (queen-bee) in tmux and auto-display it.
queue.yaml generation and management is handled entirely by the Queen inside tmux.

## Execution steps

### Step 0: Resolve package paths

```bash
PKG_DIR=$(node -e "console.log(require.resolve('queen-bee/package.json').replace('/package.json',''))")
QB_SCRIPTS_DIR="$PKG_DIR/scripts"
QB_CONTEXTS_DIR="$PKG_DIR/contexts"
```

### Step 1: Check for existing session

```bash
SESSION="qb"

tmux has-session -t "$SESSION" 2>/dev/null && {
  echo "An existing qb session was found."
  echo "  tmux attach -t qb   # monitor"
  echo "  tmux kill-session -t qb  # stop and restart"
  # Stop here. Let the user decide.
}
```

If an existing session is found, display instructions and **stop**. The user must explicitly kill the session before re-running.

### Step 2: Start tmux session

```bash
CWD=$(pwd)

tmux new-session -d -s "$SESSION" -n queen -c "$CWD" \
  "unset CLAUDECODE; QB_QUEEN=1 QB_SCRIPTS_DIR='$QB_SCRIPTS_DIR' QB_CONTEXTS_DIR='$QB_CONTEXTS_DIR' claude --dangerously-skip-permissions; echo '--- Done (press Enter to close) ---'; read"
```

### Step 2.5: Configure tmux pane display

```bash
# Show role name at top of each pane
tmux set-option -t "$SESSION" pane-border-status top

# Format: prefer @agent_label (not overridable by Claude Code), fallback to pane_title
tmux set-option -t "$SESSION" pane-border-format \
  " #{?pane_active,#[bold],}#{?@agent_label,#{@agent_label},#{pane_title}}#[default] "

# Queen pane: gold border + title
tmux select-pane -t "$SESSION:queen.0" -T "👑 queen"
tmux set-option -p -t "$SESSION:queen.0" @agent_label "👑 queen" 2>/dev/null || true
tmux set-option -p -t "$SESSION:queen.0" allow-rename off 2>/dev/null || true
tmux set-option -p -t "$SESSION:queen.0" pane-border-style "fg=yellow" 2>/dev/null || true
```

### Step 3: Auto-attach to tmux session

```bash
case "$(uname -s)" in
  Darwin)
    osascript -e '
    tell application "Terminal"
      activate
      do script "tmux attach -t qb"
    end tell
    ' 2>/dev/null || echo "Open a new terminal and run: tmux attach -t qb"
    ;;
  *)
    echo "Queen session started. Attach with: tmux attach -t qb"
    ;;
esac
```

On macOS, auto-opens Terminal.app and attaches to the tmux session.
On other platforms, prints the attach command for the user.

### Step 4: Wait for startup

```bash
for i in $(seq 1 60); do
  sleep 2
  if tmux capture-pane -t "$SESSION:queen" -p 2>/dev/null | grep -q 'Claude Code'; then
    break
  fi
done
```

Polls for up to 120 seconds. Startup is complete when the `Claude Code` banner appears.

### Step 5: Send initial prompt

If `$ARGUMENTS` is non-empty, pass the user's instruction directly. Otherwise, send a default instruction to sync issues.

```bash
if [ -n "$ARGUMENTS" ]; then
  INSTRUCTION="$ARGUMENTS"
else
  INSTRUCTION="Sync GitHub Issues to queue.yaml and complete all tasks."
fi

tmux send-keys -t "$SESSION:queen" "$INSTRUCTION"
sleep 0.3
tmux send-keys -t "$SESSION:queen" Enter
```

### Step 6: Display status to user

After startup, display:

```
Queen started (queen-bee). tmux session displayed.
  queen window: main control loop
  issue-{N}/review-{N}: Leader/Worker windows are added automatically
  tmux kill-session -t qb  # to stop
```

## Notes

- `$ARGUMENTS` contains the slash command arguments
- This command must be run in the **target project directory**
- queue.yaml generation and updates are managed by the Queen inside tmux
