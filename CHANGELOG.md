# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-02

### Added

- 3-layer orchestration system (Queen → Leader → Worker) powered by tmux
- CLI commands: `init`, `update`, `check` via `npx beeops`
- 12 skills (dispatch, review, task-decomposer, issue-sync, log-writer, self-improver, etc.)
- 3 hooks: UserPromptSubmit (context injection), Stop (log recording), PostToolUse (checkpoint)
- Locale support (en, ja) with 4-step context fallback resolution
- Context fallback system: project local (locale) → project local (root) → package (locale) → package (root)
- Environment variable chain for dynamic path resolution (BO_SCRIPTS_DIR, BO_CONTEXTS_DIR)

[0.1.0]: https://github.com/YuugouOhno/beeops/releases/tag/v0.1.0
