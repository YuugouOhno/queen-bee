# beeops

[![npm version](https://img.shields.io/npm/v/beeops)](https://www.npmjs.com/package/beeops)
[![license](https://img.shields.io/npm/l/beeops)](https://github.com/YuugouOhno/beeops/blob/main/LICENSE)
[![CI](https://github.com/YuugouOhno/beeops/actions/workflows/ci.yml/badge.svg)](https://github.com/YuugouOhno/beeops/actions/workflows/ci.yml)
[![Node.js](https://img.shields.io/node/v/beeops)](https://nodejs.org)

3-layer multi-agent orchestration system (Queen → Leader → Worker) for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), powered by tmux.

## Prerequisites

- **Node.js** >= 18
- **git**
- **tmux**
- **python3**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (`claude`)
- [GitHub CLI](https://cli.github.com/) (`gh`)

## Installation

```bash
npm install beeops
npx beeops init
```

## Quick Start

Run `/bee-dev` in Claude Code to start the Queen. She'll sync GitHub Issues, dispatch Leaders to git worktrees, and manage the full workflow — from implementation through code review and CI checks.

```
Queen (orchestrator)
  ├─ Leader          → decomposes issue, dispatches Workers, creates PR
  │    ├─ Worker (coder)
  │    └─ Worker (tester)
  └─ Review Leader   → dispatches review Workers, aggregates findings
       ├─ Worker (code-reviewer)
       ├─ Worker (security)
       └─ Worker (test-auditor)
```

Each layer runs as a separate Claude Code instance in a tmux pane. Communication flows through YAML reports and `tmux wait-for` signals. No external servers or databases required.

Attach with `tmux attach -t bee-dev` to watch all agents work in real-time.

## Architecture

- **Queen** (L1) — Reads GitHub Issues, builds a queue, dispatches Leaders and Review Leaders
- **Leader** (L2) — Decomposes an issue into subtasks, launches Workers in parallel, creates PRs
- **Review Leader** (L2) — Launches review Workers, aggregates findings, approves or requests fixes
- **Workers** (L3) — Execute a single subtask: coding, testing, or reviewing

The system includes **10 specialized skills**, **1 hook** (UserPromptSubmit for context injection), and **locale support** (en/ja) with a 4-step fallback chain.

Workers receive multi-layer context injection (base + specialization), so each role gets tailored instructions while sharing common autonomous-operation rules.

## Configuration

```bash
npx beeops init [options]
```

| Option | Description |
|--------|-------------|
| `--local` (default) | Register hooks in `.claude/settings.local.json` (personal use) |
| `--shared` | Register hooks in `.claude/settings.json` (team-shared, git committed) |
| `-g`, `--global` | Register hooks in `~/.claude/settings.json` (all projects) |
| `--with-contexts` | Copy default context files locally for customization |
| `--locale <lang>` | Set locale (`en` default, `ja` available) |

To customize agent behavior, run `npx beeops init --with-contexts` and edit files in `.beeops/contexts/`. Delete any file to fall back to the package default.

To update beeops in an existing project:

```bash
npm update beeops
npx beeops init
```

This updates the package and re-deploys commands, skills, and hooks. Your custom contexts in `.beeops/contexts/` are preserved.

To verify your installation:

```bash
npx beeops check
```

## License

MIT
