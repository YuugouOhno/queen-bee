---
name: qb-self-improver
description: Analyze accumulated log JSONL to automatically improve skills, commands, and agents. Runs automatically on session exit.
argument-hint: ["scan" or date]
---

# qb-self-improver: Self-Improvement

Analyze accumulated log JSONL to improve skills, commands, and agents.

## Scan Targets

Resources exist in two layers: global and project. **Scan both.**

| Target | Global (`~/.claude/`) | Project (`.claude/`) |
|--------|--------------------------|--------------------------|
| Skills | `~/.claude/skills/` | `.claude/skills/` |
| Commands | `~/.claude/commands/` | `.claude/commands/` |
| Agents | `~/.claude/agents/` | `.claude/agents/` |

## Procedure

### 1. Run Analysis Script (Automates Steps 1-4)

```bash
python3 .claude/skills/qb-self-improver/scripts/analyze.py
```

The script performs all of the following in batch and outputs JSON:
- Log path resolution (via `resolve-log-path.py`)
- Cursor management + analysis mode determination
- Diff log extraction
- Resource usage frequency tallying (skills_used / agents_used / commands_used)
- Rule-based agent gap detection
- Error-skill correlation analysis (effectiveness)

**Output JSON structure:**

```json
{
  "status": { "total", "cursor", "new_lines", "mode" },
  "frequency": {
    "counts": { "skills": {}, "agents": {}, "commands": {} },
    "classification": { "skills": { "high", "low", "unused" }, ... }
  },
  "all_resources": { "skills": [], "agents": [], "commands": [] },
  "agent_gaps": { "agent_name": { "missed": N, "examples": [...] } },
  "effectiveness": {
    "total_entries", "error_entries",
    "repeated_error_tags", "skills_with_errors", "effective_skills"
  },
  "entries": [{ "title", "category", "has_errors", "learnings", "patterns" }]
}
```

- `status.mode == "no_new"` → "No new logs" — exit
- `status.mode == "diff+full"` → In addition to diff analysis, also read `$LOG_BASE/self-improve/*.md` for long-term trends

### 2. Skill Gap Analysis (LLM Judgment)

The script only detects rule-based agent gaps. **Skill gaps must be judged by the LLM.**

```
Procedure:
1. Review entries in the output JSON
2. From each entry's category + learnings, infer "which skill should have been used"
3. Compare with actual skills_used
4. Tally the gaps
```

### 3. Reduction Evaluation (LLM Judgment)

Steps 1-2 produce "add/update" candidates, but **evaluate reductions first**. Prioritize reduction over addition.

| Check Item | Criteria | Action |
|---|---|---|
| Unused resources | 0 usage in frequency + similar resource exists | Merge or delete |
| Highly duplicated | Two skills with 80%+ content overlap | Merge into one |
| Bloated content | 15+ checklist items, or SKILL.md > 200 lines | Remove items / split to references |
| Out-of-date content | Content doesn't match current code | Update to match or delete section |
| Verbose description | Description > 2 lines, or repeats common knowledge | Simplify |

**Required output**: Must explicitly state one of:
- Reduction candidates found → List specific resource names and reduction details
- No reduction targets → State rationale in one line (e.g., "All skills used within past 2 weeks, no duplicates")

### 4. Execute Resource Improvements (LLM Judgment)

Based on Steps 1-3, improve resources following the reference documents below.
**Execute reductions (Step 3) before additions/updates.**

| Target | Reference Document | Content |
|--------|-------------------|---------|
| Skills | `refs/skill-manager.md` | Creation/merge/deletion criteria, naming rules |
| Commands | `refs/command-manager.md` | Creation/update/merge/deletion criteria, format |
| Agents | `refs/agent-manager.md` | Creation/merge/deletion criteria, format |

After executing improvements, record to `log.jsonl` via qb-log-writer. Include creation/update details in the `resources_created` field.

### 5. Update Cursor

```bash
python3 .claude/skills/qb-self-improver/scripts/analyze.py --update-cursor
```

### 6. Persist Analysis Results & Record to Log

1. **Persist analysis results**: Save to `$LOG_BASE/self-improve/{YYYY-MM-DD}.md`

```markdown
# {YYYY-MM-DD} self-improve analysis results

## Analysis Scope
- Log lines: {cursor+1} to {total} ({new_lines} lines)
- Mode: diff analysis / diff+full analysis

## Frequency
| Resource Type | Name | Usage Count | Classification |
|---|---|---|---|

## Gaps
| Resource Type | Name | Missed Count | Representative Miss Pattern |
|---|---|---|---|

## Reduction Evaluation
| Target Resource | Decision | Rationale |
|---|---|---|

*Even if no reduction targets, state the rationale*

## Effectiveness
| Pattern | Details |
|---|---|

## Improvement Actions Taken
- ...
```

2. **Log recording**: Record improvement actions to `log.jsonl` via qb-log-writer skill format.

## Rules

- Execute all creation, update, deletion, merge, and split actions automatically, leaving a log
- Never delete log JSONL (permanent storage)
- Do not end with "text edits only". Always execute frequency analysis and duplication analysis, recording results
