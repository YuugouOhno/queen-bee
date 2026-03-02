---
name: qb-log-writer
description: Record work logs to JSONL. Extract changes, decisions, error resolutions, and learnings from git diff and conversation context.
---

# qb-log-writer: Work Log Recording

Record session work to `.claude/queen-bee/logs/log.jsonl` in JSONL format.

## Procedure

1. Get log path and current timestamp:
   ```bash
   LOG_BASE=$(python3 "$(dirname "$(python3 -c "import queen_bee; print(queen_bee.__file__)" 2>/dev/null || echo "$QB_CONTEXTS_DIR/../hooks/resolve-log-path.py")")/resolve-log-path.py" 2>/dev/null || python3 hooks/resolve-log-path.py) && mkdir -p "$LOG_BASE" && date '+%Y-%m-%dT%H:%M:%S'
   ```
   If the above fails, use the simpler fallback:
   ```bash
   LOG_BASE=".claude/queen-bee/logs" && mkdir -p "$LOG_BASE" && date '+%Y-%m-%dT%H:%M:%S'
   ```
2. Check changed files with `git diff --name-only` and `git status`
3. Extract work content, intent, errors, and learnings from conversation context
4. Append JSONL entry to `$LOG_BASE/log.jsonl`

## Log Format (JSONL)

File: `$LOG_BASE/log.jsonl`
One line = one JSON object per work unit. All entries appended to a single file.

```json
{
  "timestamp": "2026-03-02T14:30:00",
  "title": "Brief work title",
  "category": "implementation | review | design | bugfix | refactor | research | meta",
  "changes": [{ "file": "src/domain/foo.ts", "description": "Added validation" }],
  "decisions": [
    { "what": "What was decided", "why": "Rationale", "alternatives": "Alternatives considered" }
  ],
  "errors": [
    {
      "message": "Error message",
      "cause": "Root cause",
      "solution": "How it was resolved",
      "tags": ["prisma", "enum"]
    }
  ],
  "learnings": ["Reusable insights"],
  "patterns": ["Recurring patterns observed"],
  "remaining": ["Unresolved issues / TODOs"],
  "skills_used": ["qb-task-decomposer"],
  "agents_used": ["code-reviewer", "planner"],
  "commands_used": ["commit", "review"],
  "resources_created": [{ "type": "skill", "name": "meta-task-planner", "action": "created" }]
}
```

### Field Description

| Field               | Required  | Purpose                              |
| ------------------- | --------- | ------------------------------------ |
| `timestamp`         | Required  | Chronological tracking               |
| `title`             | Required  | Summary generation, search           |
| `category`          | Required  | Pattern classification               |
| `changes`           | Required  | Change tracking, design change detection |
| `decisions`         | Required  | Knowledge capture of reasoning       |
| `errors`            | When applicable | Error knowledge accumulation     |
| `learnings`         | When applicable | Generic knowledge extraction     |
| `patterns`          | When applicable | Recurring operation detection    |
| `remaining`         | When applicable | Remaining issue tracking         |
| `skills_used`       | When applicable | Usage frequency analysis         |
| `agents_used`       | When applicable | Usage frequency analysis         |
| `commands_used`     | When applicable | Usage frequency analysis         |
| `resources_created` | When applicable | Resource change recording        |

### Omission Rules

- `errors`, `learnings`, `patterns`, `remaining`, `skills_used`, `agents_used`, `commands_used`, `resources_created` may be omitted when not applicable (exclude the key entirely)
- `decisions` must never be omitted — always record at least one
- `changes` must come from git diff, never guessed

## Deduplication Check (Required)

Before appending, verify no duplicates exist:

1. Read the last 50 lines of `log.jsonl` with the Read tool
2. Check if any planned entry's `title` is similar to existing entries
3. Skip if the same session content has already been recorded

**Dedup criteria (skip if any match):**
- Exact title match
- Title keywords match AND same category
- Same changes (2+ matching file paths) already exist
- Same category + same file changes recorded within the last 24 hours

## Rules

- **timestamp MUST be obtained via `date` command. LLM must never fabricate timestamps**
- One log entry = one line (JSONL), appended
- When multiple turn summaries are provided, append one line per turn
- Increment timestamp by 1 second between turns to avoid duplicates
- `decisions` must never be omitted — always record why
- Logs must be fact-based. No embellishment or opinions
