Launch a Creator ↔ Reviewer content quality loop (bee-content) in tmux.

## Execution steps

### Step 0: Interactive setup

Parse `$ARGUMENTS` first, then interactively ask for any missing values before launching tmux.

#### 0a. Parse $ARGUMENTS

- **instruction**: everything before the first `--` flag (or the entire string if no flags)
- **--criteria "..."**: quality criteria
- **--threshold N**: score threshold (integer)
- **--max-loops N**: maximum loop count (integer)
- **--count N**: number of pieces to generate (integer, batch mode when >= 2)
- **--name <name>**: session name for resuming later

#### 0b. Ask for missing values (always ask interactively — do NOT use defaults silently)

Use `AskUserQuestion` for each missing value in order:

**1. Instruction** (if not provided in $ARGUMENTS):
```
What content do you want to create?
```

**2. Criteria** (always ask, even if instruction was provided — unless explicitly given via --criteria):
```
What are the quality criteria for this content?
Examples: "Technically accurate, includes code examples, under 800 words"
         "Compelling headline, clear value prop, no jargon"
(Press Enter to use default: "High quality, accurate, engaging, and well-structured.")
```
If the user presses Enter or gives an empty response, use the default: `"High quality, accurate, engaging, and well-structured."`

**3. Threshold** (ask only if not provided via --threshold):
```
What score should the content reach to be accepted? (0-100, default: 80)
```
If empty, use `80`.

**4. Max loops** (ask only if not provided via --max-loops):
```
How many Creator ↔ Reviewer loops at most? (default: 3)
```
If empty, use `3`.

#### 0c. Count (ask only if not provided via --count):
```
How many pieces of content do you want to generate? (default: 1)
```
If empty, use `1` (backward compatible single-piece mode).

#### 0d. Name (always ask — skip if --name was provided):
```
Give this session a name for later resuming? (Enter to skip, use timestamp)
```
If empty, leave blank (will use timestamp in Step 2).

After collecting all values, display a summary and confirm before proceeding:
```
Ready to start bee-content:
  instruction: {INSTRUCTION}
  criteria:    {CRITERIA}
  threshold:   {THRESHOLD}/100
  max_loops:   {MAX_LOOPS}
  count:       {COUNT}

Start? (Y/n)
```
If the user says no or n, stop here.

#### Resume mode

If `--name <name>` was provided and `.beeops/tasks/content/<name>` exists, show the resume prompt instead:
```
Resume session '<name>'?
  approved: {approved from state.yaml}/{count from state.yaml}
  loop:     {current_loop from state.yaml}
  task:     {first 60 chars of instruction.txt}
Resume? (Y/n)
```
Read `approved`, `current_loop`, and `count` from `.beeops/tasks/content/<name>/state.yaml`.
Read instruction preview from `.beeops/tasks/content/<name>/instruction.txt`.
If yes, skip Step 2 initialization and go directly to Step 3 using the existing task directory.

### Step 1: Resolve package paths

```bash
PKG_DIR=$(node -e "console.log(require.resolve('beeops/package.json').replace('/package.json',''))")
BO_SCRIPTS_DIR="$PKG_DIR/scripts"
BO_CONTEXTS_DIR="$PKG_DIR/contexts"
```

### Step 2: Create task directory and files

```bash
# Use provided name or timestamp
TASK_ID="${NAME:-$(date +%Y%m%d-%H%M%S)}"
TASK_DIR=".beeops/tasks/content/$TASK_ID"

# Initialize only when not resuming
mkdir -p "$TASK_DIR/items/pending" "$TASK_DIR/items/approved" "$TASK_DIR/items/rejected"
mkdir -p "$TASK_DIR/reviews" "$TASK_DIR/prompts"
echo "$INSTRUCTION" > "$TASK_DIR/instruction.txt"
echo "$CRITERIA" > "$TASK_DIR/criteria.txt"

# state.yaml (new sessions only)
cat > "$TASK_DIR/state.yaml" <<EOF
name: ${TASK_ID}
count: ${COUNT}
approved: 0
current_loop: 0
EOF
```

### Step 3: Ensure bo tmux session exists

```bash
SESSION="bee-content"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  CWD=$(pwd)
  tmux new-session -d -s "$SESSION" -c "$CWD"
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format \
    " #{?pane_active,#[bold],}#{?@agent_label,#{@agent_label},#{pane_title}}#[default] "
fi
```

### Step 4: Create tmux window and launch loop

```bash
tmux new-window -t "$SESSION" -n "content-$TASK_ID" \
  "BO_CONTEXTS_DIR='$BO_CONTEXTS_DIR' BO_SCRIPTS_DIR='$BO_SCRIPTS_DIR' bash '$BO_SCRIPTS_DIR/launch-content-loop.sh' '$TASK_ID' '$TASK_DIR' '$THRESHOLD' '$MAX_LOOPS' '$COUNT'; echo '--- Done (press Enter) ---'; read"

# Set title for pane 0 (orchestrator)
tmux select-pane -t "$SESSION:content-$TASK_ID.0" -T "🐝 content-$TASK_ID"
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" @agent_label "🐝 content-$TASK_ID" 2>/dev/null || true
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" allow-rename off 2>/dev/null || true
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" pane-border-style "fg=yellow" 2>/dev/null || true
```

### Step 5: Auto-attach to tmux session

```bash
case "$(uname -s)" in
  Darwin)
    osascript -e '
    tell application "Terminal"
      activate
      do script "tmux attach -t bee-content"
    end tell
    ' 2>/dev/null || echo "Open a new terminal and run: tmux attach -t bee-content"
    ;;
  *)
    echo "Content loop started. Attach with: tmux attach -t bee-content"
    ;;
esac
```

On macOS, auto-opens Terminal.app and attaches to the tmux session.
On other platforms, prints the attach command for the user.

### Step 6: Display status message

Display the following to the user (adapt based on COUNT):

**When COUNT=1 (single mode):**
```
bee-content started.
  task_id:   {TASK_ID}
  threshold: {THRESHOLD}/100
  max_loops: {MAX_LOOPS}
  output:    {TASK_DIR}/content.md

  Monitor: tmux attach -t bee-content
  Stop:    tmux kill-window -t bee-content:content-{TASK_ID}
  Resume:  /bee-content --name {TASK_ID}
```
Show the Resume line only when a named session (non-timestamp) was used.

**When COUNT>=2 (batch mode):**
```
bee-content started.
  task_id:   {TASK_ID}
  count:     {COUNT}
  threshold: {THRESHOLD}/100
  max_loops: {MAX_LOOPS}
  output:    {TASK_DIR}/items/approved/

  Monitor: tmux attach -t bee-content
  Stop:    tmux kill-window -t bee-content:content-{TASK_ID}
  Resume:  /bee-content --name {TASK_ID}
```
Show the Resume line only when a named session was used.

## Notes

- `$ARGUMENTS` contains the slash command arguments
- This command must be run in the **target project directory**
- COUNT=1: content written to `.beeops/tasks/content/{task_id}/content.md` (backward compatible)
- COUNT>=2: approved pieces written to `.beeops/tasks/content/{task_id}/items/approved/`
- Each loop: Creator writes → Reviewer audits → score checked against threshold
- Loop log at: `.beeops/tasks/content/{task_id}/loop.log`
- Session state tracked in `.beeops/tasks/content/{task_id}/state.yaml`
