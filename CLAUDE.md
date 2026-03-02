# queen-bee

3-layer multi-agent orchestration system for Claude Code (Queen → Leader → Worker).

## Package Overview

Run `/qb` in Claude Code to launch a tmux-based multi-agent system.
Install with `npm install queen-bee` + `npx queen-bee init` in any project.

## Core Design: Environment Variable Chain

Eliminates hardcoded paths by dynamically resolving the package install location:

```
/qb execution → PKG_DIR resolved via require.resolve('queen-bee/package.json')
  → QB_SCRIPTS_DIR="$PKG_DIR/scripts"
  → QB_CONTEXTS_DIR="$PKG_DIR/contexts"
  → Injected as env vars when starting tmux session
  → Queen → launch-leader.sh (bakes QB_* into wrapper)
  → Leader → launch-worker.sh (bakes QB_* into wrapper)
  → Worker execution
```

## Context Resolution: 4-Step Locale Fallback

prompt-context.py resolves context files in the following order:

```
1. Project local (locale): <project>/.claude/queen-bee/contexts/<locale>/<file>
2. Project local (root):   <project>/.claude/queen-bee/contexts/<file>
3. Package (locale):        <pkg>/contexts/<locale>/<file>
4. Package (root):          <pkg>/contexts/<file>
```

- Local files take priority when present
- Falls back to package defaults for missing local files
- `agent-modes.json` follows the same fallback rules
- Locale determined by QB_LOCALE env var or `.claude/queen-bee/locale` file
- `npx queen-bee init --with-contexts` copies defaults locally for customization

## Directory Structure

```
queen-bee/
├── package.json                         # npm package definition
├── bin/queen-bee.js                     # CLI: init / update / check
├── scripts/
│   ├── launch-leader.sh                 # Launch Leader/Review Leader in tmux window
│   └── launch-worker.sh                 # Launch Worker in tmux pane
├── hooks/
│   ├── prompt-context.py                # UserPromptSubmit hook (env var → context injection)
│   ├── run-log.py                       # Stop hook (session-end log recording)
│   ├── checkpoint.py                    # PostToolUse hook (mid-session checkpoint)
│   └── resolve-log-path.py             # Log directory path resolver utility
├── contexts/                            # Package default contexts
│   ├── en/                              # English locale
│   │   ├── queen.md
│   │   ├── leader.md
│   │   ├── review-leader.md
│   │   ├── worker-base.md              # Worker base context
│   │   ├── coder.md                    # Worker (coder) context
│   │   ├── tester.md                   # Worker (tester) context
│   │   ├── reviewer-base.md
│   │   ├── code-reviewer.md
│   │   ├── security-reviewer.md        # Worker (security reviewer) context
│   │   ├── test-auditor.md             # Worker (test auditor) context
│   │   ├── default.md                  # Default context
│   │   ├── log.md                       # Log recording agent context
│   │   ├── fb.md                        # Self-improvement agent context
│   │   └── agent-modes.json
│   ├── ja/                              # Japanese locale
│   │   └── ...
│   ├── queen.md                         # Root fallback (English)
│   ├── leader.md
│   ├── review-leader.md
│   ├── worker-base.md                  # Worker base context (root fallback)
│   ├── coder.md                        # Worker (coder) context (root fallback)
│   ├── tester.md                       # Worker (tester) context (root fallback)
│   ├── agent-modes.json                 # Env var → context file mapping
│   ├── reviewer-base.md                 # Worker (reviewer) base context
│   ├── code-reviewer.md               # Code reviewer context (root fallback)
│   ├── security-reviewer.md           # Security reviewer context (root fallback)
│   ├── test-auditor.md                # Test auditor context (root fallback)
│   ├── log.md                           # Log recording agent context (root fallback)
│   ├── fb.md                            # Self-improvement agent context (root fallback)
│   └── default.md                       # Default context (no mode active)
├── skills/
│   ├── qb-dispatch/SKILL.md             # Queen → Leader dispatch procedure
│   ├── qb-leader-dispatch/SKILL.md      # Leader → Worker dispatch procedure
│   ├── qb-task-decomposer/SKILL.md    # Task decomposition skill
│   ├── qb-issue-sync/SKILL.md         # GitHub Issue → queue.yaml sync
│   ├── qb-log-writer/SKILL.md         # Structured work log recording
│   ├── qb-self-improver/              # Self-improvement analysis
│   │   ├── SKILL.md
│   │   ├── scripts/analyze.py
│   │   └── refs/                        # Reference docs for improvement
│   ├── qb-review-backend/SKILL.md          # Backend code review
│   ├── qb-review-frontend/SKILL.md         # Frontend code review
│   ├── qb-review-database/SKILL.md         # Database/SQL review
│   ├── qb-review-operations/SKILL.md       # Infrastructure/DevOps review
│   ├── qb-review-process/SKILL.md          # Development process review
│   └── qb-review-security/SKILL.md         # Security review (cross-cutting)
└── command/
    └── qb.md                            # /qb slash command definition
```

### Files Generated in Target Project

```
<project>/
├── .claude/
│   ├── commands/qb.md                   # /qb command
│   ├── skills/
│   │   ├── qb-dispatch/SKILL.md         # Queen skill
│   │   ├── qb-leader-dispatch/SKILL.md  # Leader skill
│   │   ├── qb-task-decomposer/SKILL.md
│   │   ├── qb-issue-sync/SKILL.md
│   │   ├── qb-log-writer/SKILL.md
│   │   ├── qb-self-improver/          # With scripts/ and refs/
│   │   ├── qb-review-backend/SKILL.md
│   │   ├── qb-review-frontend/SKILL.md
│   │   ├── qb-review-database/SKILL.md
│   │   ├── qb-review-operations/SKILL.md
│   │   ├── qb-review-process/SKILL.md
│   │   └── qb-review-security/SKILL.md
│   ├── settings.local.json              # Hook registration (--local, default)
│   ├── settings.json                    # Hook registration (--shared)
│   └── queen-bee/
│       ├── locale                       # Locale preference file
│       └── contexts/                    # Custom contexts (--with-contexts only)
│           ├── en/
│           ├── ja/
│           └── ...
```

## `npx queen-bee init` Behavior

1. Prerequisites check (Node.js>=18, git, tmux, python3, claude, gh)
2. Detect project root via `git rev-parse --show-toplevel`
3. Copy `.claude/commands/qb.md`
4. Copy 12 skills to `.claude/skills/`
5. Register 3 hooks: UserPromptSubmit, Stop, PostToolUse (default: `.claude/settings.local.json`)
6. Save locale preference to `.claude/queen-bee/locale`
7. If `--with-contexts`: copy defaults to `.claude/queen-bee/contexts/`
8. Display completion message

### init Options

| Option | Hook target | Use case |
|--------|-------------|----------|
| `--local` (default) | `.claude/settings.local.json` | Personal use |
| `--shared` | `.claude/settings.json` | Team sharing (git committed) |
| `-g`, `--global` | `~/.claude/settings.json` | Global (all projects) |
| `--with-contexts` | — | Deploy contexts for customization |
| `--locale <lang>` | — | Set locale (default: en, available: en, ja) |

## Environment Variables

| Variable | Set by | Used by | Purpose |
|----------|--------|---------|---------|
| QB_QUEEN | command/qb.md | prompt-context.py | Identifies Queen agent |
| QB_LEADER | launch-leader.sh | prompt-context.py | Identifies Leader agent |
| QB_REVIEW_LEADER | launch-leader.sh | prompt-context.py | Identifies Review Leader |
| QB_WORKER_CODER | launch-worker.sh | prompt-context.py | Identifies coder Worker |
| QB_WORKER_TESTER | launch-worker.sh | prompt-context.py | Identifies tester Worker |
| QB_WORKER_CODE_REVIEWER | launch-worker.sh | prompt-context.py | Identifies code reviewer Worker |
| QB_WORKER_SECURITY | launch-worker.sh | prompt-context.py | Identifies security reviewer Worker |
| QB_WORKER_TEST_AUDITOR | launch-worker.sh | prompt-context.py | Identifies test auditor Worker |
| QB_SCRIPTS_DIR | command/qb.md | launch-*.sh | Package scripts directory |
| QB_CONTEXTS_DIR | command/qb.md | prompt-context.py | Package contexts directory |
| QB_LOCALE | user | prompt-context.py | Override locale preference |
| QB_LOG_DIR | user | resolve-log-path.py | Override log directory path |
| QB_FB_AGENT | run-log.py | prompt-context.py, checkpoint.py | Identifies log/feedback agent (loop prevention) |
| QB_FB_INCLUDE_FB | run-log.py | prompt-context.py | Includes self-improvement in feedback agent |

## Development

### Verification

```bash
cd /Users/yuugou/dev/oss/claude-ants
npm link
cd <test-project>
npm link queen-bee
npx queen-bee init
npx queen-bee init --shared
npx queen-bee init -g
npx queen-bee init --with-contexts --locale ja
npx queen-bee check
# In Claude Code: /qb → Queen launches
```

### Verification Points

1. `.claude/commands/qb.md` is generated
2. `.claude/skills/` contains all 12 skills
3. 3 hooks registered in the specified settings file (UserPromptSubmit, Stop, PostToolUse)
4. `/qb` launches Queen in tmux
5. Queen can execute `$QB_SCRIPTS_DIR/launch-leader.sh`
6. `QB_SCRIPTS_DIR`/`QB_CONTEXTS_DIR` propagate to Leader/Worker
7. `prompt-context.py` resolves contexts with locale fallback
8. Deleting a local file falls back to package default
9. Stop hook triggers log recording on session exit
10. PostToolUse hook triggers checkpoint after threshold edits
11. Review skills are invoked by code-reviewer via resource routing
