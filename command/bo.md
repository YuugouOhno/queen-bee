Launch a Queen session (beeops) in tmux and auto-display it.
queue.yaml generation and management is handled entirely by the Queen inside tmux.

## Execution steps

### Step 0: Resolve package paths

```bash
PKG_DIR=$(node -e "console.log(require.resolve('beeops/package.json').replace('/package.json',''))")
BO_SCRIPTS_DIR="$PKG_DIR/scripts"
BO_CONTEXTS_DIR="$PKG_DIR/contexts"
```

### Step 1: Check for existing session

```bash
SESSION="bo"

tmux has-session -t "$SESSION" 2>/dev/null && {
  echo "An existing bo session was found."
  echo "  tmux attach -t bo   # monitor"
  echo "  tmux kill-session -t bo  # stop and restart"
  # Stop here. Let the user decide.
}
```

If an existing session is found, display instructions and **stop**. The user must explicitly kill the session before re-running.

### Step 2: Start tmux session

```bash
CWD=$(pwd)

tmux new-session -d -s "$SESSION" -n queen -c "$CWD" \
  "unset CLAUDECODE; BO_QUEEN=1 BO_SCRIPTS_DIR='$BO_SCRIPTS_DIR' BO_CONTEXTS_DIR='$BO_CONTEXTS_DIR' claude --dangerously-skip-permissions; echo '--- Done (press Enter to close) ---'; read"
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
      do script "tmux attach -t bo"
    end tell
    ' 2>/dev/null || echo "Open a new terminal and run: tmux attach -t bo"
    ;;
  *)
    echo "Queen session started. Attach with: tmux attach -t bo"
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

### Step 5: Resolve execution mode and send initial prompt

Determine what instruction to send to the Queen. Priority order:

1. **`$ARGUMENTS` provided** → use it directly, skip settings/interactive
2. **Settings file exists** (`.claude/beeops/settings.json`) → build instruction from settings
3. **No arguments and no settings** → ask the user interactively

#### 5a. If `$ARGUMENTS` is non-empty

Use it directly:

```bash
if [ -n "$ARGUMENTS" ]; then
  INSTRUCTION="$ARGUMENTS"
fi
```

#### 5b. If no arguments, check for settings file

```bash
SETTINGS_FILE=".claude/beeops/settings.json"
if [ -z "$ARGUMENTS" ] && [ -f "$SETTINGS_FILE" ]; then
  echo "Found settings: $SETTINGS_FILE"
  cat "$SETTINGS_FILE"
fi
```

If the settings file exists, build the instruction based on its contents:

| Field | Type | Description |
|-------|------|-------------|
| `issues` | `number[]` | Specific issue numbers to process (e.g. `[42, 55]`) |
| `assignee` | `string` | `"me"` = only issues assigned to the current GitHub user, `"all"` = all open issues |
| `skip_review` | `boolean` | Skip review phase if true (default: false) |
| `priority` | `string` | Only process issues of this priority or higher (`"high"`, `"medium"`, `"low"`) |
| `labels` | `string[]` | Only process issues with these labels |

Build the `INSTRUCTION` string as follows:
- If `issues` is set: `"Sync GitHub Issues to queue.yaml and process only issues: #42, #55."`
- If `assignee` is `"me"`: `"Sync GitHub Issues to queue.yaml and process only issues assigned to me."`
- If `assignee` is `"all"` or not set: `"Sync GitHub Issues to queue.yaml and complete all tasks."`
- Append options: if `skip_review` is true, append `" Skip the review phase."`. If `priority` is set, append `" Only process issues with priority {priority} or higher."`. If `labels` is set, append `" Only process issues with labels: {labels}."`

#### 5c. If no arguments and no settings file, ask the user interactively

Present the following choices to the user (use AskUserQuestion or display the options and wait for input):

```
How should the Queen process issues?

1. Specify issue numbers (e.g. 42, 55, 100)
2. Only issues assigned to me
3. All open issues

Enter your choice (1/2/3):
```

Based on the user's response:
- **Choice 1**: Ask for issue numbers, then set `INSTRUCTION="Sync GitHub Issues to queue.yaml and process only issues: #42, #55."`
- **Choice 2**: Set `INSTRUCTION="Sync GitHub Issues to queue.yaml and process only issues assigned to me."`
- **Choice 3**: Set `INSTRUCTION="Sync GitHub Issues to queue.yaml and complete all tasks."`

Optionally, after the mode is selected, ask:
```
Save this as default settings? (y/n)
```
If yes, write the corresponding `.claude/beeops/settings.json` file so the next run uses it automatically.

#### 5d. Send the instruction to the Queen

```bash
tmux send-keys -t "$SESSION:queen" "$INSTRUCTION"
sleep 0.3
tmux send-keys -t "$SESSION:queen" Enter
```

### Step 6: Display status to user

After startup, display:

```
Queen started (beeops). tmux session displayed.
  queen window: main control loop
  issue-{N}/review-{N}: Leader/Worker windows are added automatically
  tmux kill-session -t bo  # to stop
```

## Notes

- `$ARGUMENTS` contains the slash command arguments
- This command must be run in the **target project directory**
- queue.yaml generation and updates are managed by the Queen inside tmux
