# queen-bee

3-layer multi-agent orchestration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

**Queen → Leader → Worker** — automatically decomposes GitHub Issues into subtasks, implements them in parallel using git worktree isolation, runs code reviews, and checks CI — all orchestrated through tmux.

## How It Works

```
Queen (L1)          – Reads GitHub Issues, builds queue.yaml, dispatches Leaders
  └─ Leader (L2)    – Decomposes issue into subtasks, dispatches Workers, creates PR
       └─ Worker (L3) – Executes a single subtask (code, test, review, security audit)
```

Each layer runs as a separate Claude Code instance:
- **Queen** = tmux session (gold border)
- **Leader** = tmux window per issue (blue border), with git worktree isolation
- **Worker** = tmux pane within Leader's window

Communication flows through YAML reports and `tmux wait-for` signals. No external servers, databases, or APIs beyond GitHub.

## Prerequisites

- **Node.js** >= 18
- **git**
- **tmux**
- **python3**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (`claude`)
- [GitHub CLI](https://cli.github.com/) (`gh`) — for issue sync and PR operations

## Quick Start

```bash
# Install
npm install queen-bee

# Initialize in your project
cd your-project
npx queen-bee init

# Launch from Claude Code
# Type /qb in Claude Code
```

This installs:
- `/qb` slash command
- 4 skills (dispatch, leader-dispatch, task-decomposer, issue-sync)
- A UserPromptSubmit hook for context injection

## Init Options

```bash
npx queen-bee init                    # Hook in .claude/settings.local.json (default)
npx queen-bee init --shared           # Hook in .claude/settings.json (team-shared)
npx queen-bee init --global           # Hook in ~/.claude/settings.json (all projects)
npx queen-bee init --with-contexts    # Copy context files for customization
npx queen-bee init --locale ja        # Set locale to Japanese
```

## Multi-Language Support

queen-bee supports multiple locales for agent prompts. Currently available: **en** (English, default), **ja** (Japanese).

```bash
# Set during init
npx queen-bee init --locale ja

# Override at runtime
QB_LOCALE=ja /qb
```

Context files are resolved with a 4-step fallback:
1. Project local + locale (`<project>/.claude/queen-bee/contexts/<locale>/<file>`)
2. Project local root (`<project>/.claude/queen-bee/contexts/<file>`)
3. Package + locale (`<pkg>/contexts/<locale>/<file>`)
4. Package root (`<pkg>/contexts/<file>`)

## Customizing Agent Behavior

```bash
# Copy default contexts for editing
npx queen-bee init --with-contexts
```

This creates `.claude/queen-bee/contexts/` in your project. Edit any file to customize agent behavior. Delete a file to fall back to the package default.

Key files:
- `queen.md` — Queen orchestrator system prompt
- `leader.md` — Implementation Leader prompt
- `review-leader.md` — Review Leader prompt
- `executor.md` — Worker (coder/tester) prompt
- `reviewer-base.md` — Worker (reviewer) prompt
- `agent-modes.json` — Environment variable to context file mapping

## Architecture

### Workflow

1. **Issue Sync**: Queen fetches open GitHub Issues → builds `queue.yaml`
2. **Dispatch**: Queen launches a Leader in a new tmux window with git worktree
3. **Implementation**: Leader decomposes issue → launches Workers in tmux panes
4. **PR Creation**: Final Worker creates a pull request
5. **Review**: Queen dispatches a Review Leader → launches review Workers
6. **CI Check**: On approval, Queen monitors CI status
7. **Fix Loop**: On review/CI failure, Queen restarts Leader in fix mode (up to 3 times)

### tmux Layout

```
tmux session "qb"
├── [queen]     👑 Queen orchestrator (gold border)
├── [issue-42]  👑 Leader for issue #42 (blue border)
│   ├── pane 0: Leader
│   ├── pane 1: Worker (coder)
│   └── pane 2: Worker (tester)
└── [review-42] 🔮 Review Leader for issue #42 (magenta border)
    ├── pane 0: Review Leader
    └── pane 1: Worker (reviewer)
```

Attach with `tmux attach -t qb` to watch all agents work in real-time.

## Verification

```bash
npx queen-bee check
```

Verifies that all components are correctly installed: command, skills, hook registration, and package resolution.

## License

MIT

## Author

[YuugouOhno](https://github.com/YuugouOhno)
# queen-bee
