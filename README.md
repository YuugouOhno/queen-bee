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

After installation, in Claude Code:

- **`/bee-dev`** — Sync GitHub Issues and run the full Queen → Leader → Worker development pipeline
- **`/bee-content`** — Run a Creator ↔ Reviewer quality loop to iteratively improve content

Each agent runs as a separate Claude Code instance in a tmux pane. Attach with `tmux attach -t bee-dev` to watch in real-time.

## Architecture

- **Queen** (L1) — Reads GitHub Issues, builds a queue, dispatches Leaders and Review Leaders
- **Leader** (L2) — Decomposes an issue into subtasks, launches Workers in parallel, creates PRs
- **Review Leader** (L2) — Launches review Workers, aggregates findings, approves or requests fixes
- **Workers** (L3) — Execute a single subtask: coding, testing, or reviewing

The system includes **10 specialized skills**, **1 hook** (UserPromptSubmit for context injection), and **locale support** (en/ja) with a 4-step fallback chain.

Workers receive multi-layer context injection (base + specialization), so each role gets tailored instructions while sharing common autonomous-operation rules.

## Commands

### `/bee-dev` — Development Orchestration

Runs the full Queen → Leader → Worker pipeline for GitHub Issues. Syncs issues, dispatches Leaders to isolated git worktrees, implements, reviews, and monitors CI.

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

### `/bee-content` — Content Quality Loop

Runs a Creator ↔ Reviewer loop to iteratively improve content until it meets a quality threshold.

```
/bee-content "Write a blog post about beeops" --criteria "Accurate, under 800 words" --threshold 85
```

The Creator writes content and self-scores it. The Reviewer evaluates independently and provides feedback. The loop continues until the threshold is met or `--max-loops` is reached.

| Option | Description |
|--------|-------------|
| `--criteria "..."` | Quality criteria for the content |
| `--threshold N` | Score threshold to accept (0–100, default: 80) |
| `--max-loops N` | Maximum Creator ↔ Reviewer iterations (default: 3) |
| `--count N` | Number of pieces to generate in batch mode |
| `--name <name>` | Session name for resuming later |

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
