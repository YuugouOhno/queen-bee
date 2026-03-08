# beeops

3-layer multi-agent orchestration system for Claude Code (Queen → Leader → Worker).

## Package Overview

Run `/bo` in Claude Code to launch a tmux-based multi-agent system.
Install with `npm install beeops` + `npx beeops init` in any project.

## Core Design: Environment Variable Chain

Eliminates hardcoded paths by dynamically resolving the package install location:

```
/bo execution → PKG_DIR resolved via require.resolve('beeops/package.json')
  → BO_SCRIPTS_DIR="$PKG_DIR/scripts"
  → BO_CONTEXTS_DIR="$PKG_DIR/contexts"
  → Injected as env vars when starting tmux session
  → Queen → launch-leader.sh (bakes BO_* into wrapper)
  → Leader → launch-worker.sh (bakes BO_* into wrapper)
  → Worker execution
```

## Context Resolution: 4-Step Locale Fallback

bo-prompt-context.py resolves context files in the following order:

```
1. Project local (locale): <project>/.claude/beeops/contexts/<locale>/<file>
2. Project local (root):   <project>/.claude/beeops/contexts/<file>
3. Package (locale):        <pkg>/contexts/<locale>/<file>
4. Package (root):          <pkg>/contexts/<file>
```

- Local files take priority when present
- Falls back to package defaults for missing local files
- `agent-modes.json` follows the same fallback rules
- Locale determined by BO_LOCALE env var or `.claude/beeops/locale` file
- `npx beeops init --with-contexts` copies defaults locally for customization

## Directory Structure

```
beeops/
├── package.json                         # npm package definition
├── bin/beeops.js                     # CLI: init / update / check
├── scripts/
│   ├── launch-leader.sh                 # Launch Leader/Review Leader in tmux window
│   └── launch-worker.sh                 # Launch Worker in tmux pane
├── hooks/
│   └── bo-prompt-context.py                # UserPromptSubmit hook (env var → context injection)
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
│   └── default.md                       # Default context (no mode active)
├── skills/
│   ├── bo-dispatch/SKILL.md             # Queen → Leader dispatch procedure
│   ├── bo-leader-dispatch/SKILL.md      # Leader → Worker dispatch procedure
│   ├── bo-task-decomposer/SKILL.md    # Task decomposition skill
│   ├── bo-issue-sync/SKILL.md         # GitHub Issue → queue.yaml sync
│   ├── bo-review-backend/SKILL.md          # Backend code review
│   ├── bo-review-frontend/SKILL.md         # Frontend code review
│   ├── bo-review-database/SKILL.md         # Database/SQL review
│   ├── bo-review-operations/SKILL.md       # Infrastructure/DevOps review
│   ├── bo-review-process/SKILL.md          # Development process review
│   └── bo-review-security/SKILL.md         # Security review (cross-cutting)
└── command/
    └── bo.md                            # /bo slash command definition
```

### Files Generated in Target Project

```
<project>/
├── .claude/
│   ├── commands/bo.md                   # /bo command
│   ├── skills/
│   │   ├── bo-dispatch/SKILL.md         # Queen skill
│   │   ├── bo-leader-dispatch/SKILL.md  # Leader skill
│   │   ├── bo-task-decomposer/SKILL.md
│   │   ├── bo-issue-sync/SKILL.md
│   │   ├── bo-review-backend/SKILL.md
│   │   ├── bo-review-frontend/SKILL.md
│   │   ├── bo-review-database/SKILL.md
│   │   ├── bo-review-operations/SKILL.md
│   │   ├── bo-review-process/SKILL.md
│   │   └── bo-review-security/SKILL.md
│   ├── settings.local.json              # Hook registration (--local, default)
│   ├── settings.json                    # Hook registration (--shared)
│   └── beeops/
│       ├── locale                       # Locale preference file
│       └── contexts/                    # Custom contexts (--with-contexts only)
│           ├── en/
│           ├── ja/
│           └── ...
```

## `npx beeops init` Behavior

1. Prerequisites check (Node.js>=18, git, tmux, python3, claude, gh)
2. Detect project root via `git rev-parse --show-toplevel`
3. Copy `.claude/commands/bo.md`
4. Copy 10 skills to `.claude/skills/`
5. Register 1 hook: UserPromptSubmit (default: `.claude/settings.local.json`)
6. Save locale preference to `.claude/beeops/locale`
7. If `--with-contexts`: copy defaults to `.claude/beeops/contexts/`
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
| BO_QUEEN | command/bo.md | bo-prompt-context.py | Identifies Queen agent |
| BO_LEADER | launch-leader.sh | bo-prompt-context.py | Identifies Leader agent |
| BO_REVIEW_LEADER | launch-leader.sh | bo-prompt-context.py | Identifies Review Leader |
| BO_WORKER_CODER | launch-worker.sh | bo-prompt-context.py | Identifies coder Worker |
| BO_WORKER_TESTER | launch-worker.sh | bo-prompt-context.py | Identifies tester Worker |
| BO_WORKER_CODE_REVIEWER | launch-worker.sh | bo-prompt-context.py | Identifies code reviewer Worker |
| BO_WORKER_SECURITY | launch-worker.sh | bo-prompt-context.py | Identifies security reviewer Worker |
| BO_WORKER_TEST_AUDITOR | launch-worker.sh | bo-prompt-context.py | Identifies test auditor Worker |
| BO_SCRIPTS_DIR | command/bo.md | launch-*.sh | Package scripts directory |
| BO_CONTEXTS_DIR | command/bo.md | bo-prompt-context.py | Package contexts directory |
| BO_LOCALE | user | bo-prompt-context.py | Override locale preference |

## Development

### Verification

```bash
cd /Users/yuugou/dev/oss/claude-ants
npm link
cd <test-project>
npm link beeops
npx beeops init
npx beeops init --shared
npx beeops init -g
npx beeops init --with-contexts --locale ja
npx beeops check
# In Claude Code: /bo → Queen launches
```

### Verification Points

1. `.claude/commands/bo.md` is generated
2. `.claude/skills/` contains all 10 skills
3. 1 hook registered in the specified settings file (UserPromptSubmit)
4. `/bo` launches Queen in tmux
5. Queen can execute `$BO_SCRIPTS_DIR/launch-leader.sh`
6. `BO_SCRIPTS_DIR`/`BO_CONTEXTS_DIR` propagate to Leader/Worker
7. `bo-prompt-context.py` resolves contexts with locale fallback
8. Deleting a local file falls back to package default
9. Review skills are invoked by code-reviewer via resource routing
