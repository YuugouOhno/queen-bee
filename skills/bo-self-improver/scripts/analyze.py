#!/usr/bin/env python3
"""Analyze log.jsonl for self-improvement structured reports.

Performs cursor management, diff extraction, frequency tallying, agent gap detection,
and effectiveness analysis in batch, outputting JSON for the LLM to make improvement decisions.

Usage:
    python3 analyze.py                    # Auto-detect log path
    python3 analyze.py --log-base PATH    # Explicit log path
    python3 analyze.py --update-cursor    # Update cursor after analysis
"""

import json
import subprocess
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Log path resolution (delegate to resolve-log-path.py)
# ---------------------------------------------------------------------------

def _find_resolve_script() -> Path | None:
    """Find resolve-log-path.py via multiple strategies."""
    import os

    # Strategy 1: QB_CONTEXTS_DIR env var
    ctx_dir = os.environ.get("QB_CONTEXTS_DIR")
    if ctx_dir:
        candidate = Path(ctx_dir).parent / "hooks" / "resolve-log-path.py"
        if candidate.exists():
            return candidate

    # Strategy 2: Relative to this script (package layout)
    candidate = Path(__file__).resolve().parent.parent.parent / "hooks" / "resolve-log-path.py"
    if candidate.exists():
        return candidate

    # Strategy 3: require.resolve
    try:
        pkg_dir = subprocess.run(
            ["node", "-e", "console.log(require.resolve('queen-bee/package.json').replace('/package.json',''))"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        candidate = Path(pkg_dir) / "hooks" / "resolve-log-path.py"
        if candidate.exists():
            return candidate
    except Exception:
        pass

    return None


def resolve_log_base() -> Path:
    resolver = _find_resolve_script()
    if resolver:
        result = subprocess.run(
            [sys.executable, str(resolver)],
            capture_output=True, text=True, check=True
        )
        return Path(result.stdout.strip())
    # Fallback
    return Path.cwd() / ".claude" / "queen-bee" / "logs"


# ---------------------------------------------------------------------------
# Step 1: Status check & analysis mode determination
# ---------------------------------------------------------------------------

def check_status(log_base: Path) -> dict:
    log_file = log_base / "log.jsonl"
    cursor_file = log_base / "self-improve/.cursor"
    last_full_file = log_base / "self-improve/.last-full"

    if not log_file.exists():
        return {"total": 0, "cursor": 0, "new_lines": 0, "mode": "no_log"}

    total = sum(1 for _ in open(log_file, encoding="utf-8"))
    cursor = int(cursor_file.read_text().strip()) if cursor_file.exists() else 0
    new_lines = total - cursor

    if new_lines <= 0:
        return {"total": total, "cursor": cursor, "new_lines": 0, "mode": "no_new"}

    last_full = last_full_file.read_text().strip() if last_full_file.exists() else "1970-01-01"
    try:
        last_full_date = datetime.strptime(last_full, "%Y-%m-%d").date()
        days_since_full = (date.today() - last_full_date).days
    except ValueError:
        days_since_full = 999

    mode = "diff"
    if new_lines >= 50 or days_since_full >= 5:
        mode = "diff+full"

    return {
        "total": total,
        "cursor": cursor,
        "new_lines": new_lines,
        "mode": mode,
        "last_full": last_full,
        "days_since_full": days_since_full,
    }


# ---------------------------------------------------------------------------
# Diff entry extraction
# ---------------------------------------------------------------------------

def get_diff_entries(log_base: Path, cursor: int) -> list[dict]:
    """Get new log entries after the cursor."""
    log_file = log_base / "log.jsonl"
    entries = []
    with open(log_file, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            if i <= cursor:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


# ---------------------------------------------------------------------------
# Step 2: Frequency analysis
# ---------------------------------------------------------------------------

def list_resources() -> dict[str, list[str]]:
    """Get existing resource lists from both global and project locations."""
    result: dict[str, set[str]] = {"skills": set(), "agents": set(), "commands": set()}

    for base in [Path.home() / ".claude", Path.cwd() / ".claude"]:
        skills_dir = base / "skills"
        if skills_dir.exists():
            for d in skills_dir.iterdir():
                if d.is_dir() and (d / "SKILL.md").exists():
                    result["skills"].add(d.name)
        agents_dir = base / "agents"
        if agents_dir.exists():
            for f in agents_dir.glob("*.md"):
                if f.name != "README.md":
                    result["agents"].add(f.stem)
        commands_dir = base / "commands"
        if commands_dir.exists():
            for f in commands_dir.glob("*.md"):
                if f.name != "README.md":
                    result["commands"].add(f.stem)

    return {k: sorted(v) for k, v in result.items()}


def analyze_frequency(entries: list[dict], all_resources: dict) -> dict:
    """Tally skills_used / agents_used / commands_used in diff logs."""
    counts: dict[str, Counter] = {
        "skills": Counter(),
        "agents": Counter(),
        "commands": Counter(),
    }

    for entry in entries:
        for s in entry.get("skills_used", []):
            counts["skills"][s] += 1
        for a in entry.get("agents_used", []):
            counts["agents"][a] += 1
        for c in entry.get("commands_used", []):
            counts["commands"][c] += 1

    def classify(counter: Counter, all_names: list[str]) -> dict:
        used = set(counter.keys())
        return {
            "high": sorted(n for n in used if counter[n] >= 3),
            "low": sorted(n for n in used if 0 < counter[n] < 3),
            "unused": sorted(n for n in all_names if n not in used),
        }

    return {
        "counts": {k: dict(v.most_common()) for k, v in counts.items()},
        "classification": {
            k: classify(counts[k], all_resources[k]) for k in counts
        },
    }


# ---------------------------------------------------------------------------
# Step 3: Agent gap analysis (rule-based)
# ---------------------------------------------------------------------------

AGENT_RULES = [
    {
        "agent": "code-reviewer",
        "match": lambda e: (
            "review" in e.get("category", "").lower()
            or e.get("category", "").lower() in ("implementation", "bugfix")
        ),
    },
    {
        "agent": "build-error-resolver",
        "match": lambda e: (
            bool(e.get("errors"))
            and any(
                t in tag
                for err in e.get("errors", [])
                for tag in err.get("tags", [])
                for t in ("build", "type", "prisma", "tsc")
            )
        ),
    },
    {
        "agent": "database-reviewer",
        "match": lambda e: any(
            "prisma" in c.get("file", "") or "migration" in c.get("file", "")
            for c in e.get("changes", [])
        ),
    },
    {
        "agent": "refactor-cleaner",
        "match": lambda e: "refactor" in e.get("category", "").lower(),
    },
    {
        "agent": "planner",
        "match": lambda e: (
            "Phase" in e.get("title", "")
            or len(e.get("changes", [])) >= 8
        ),
    },
    {
        "agent": "security-reviewer",
        "match": lambda e: any(
            any(kw in c.get("file", "").lower() for kw in ("auth", "security", "rls"))
            for c in e.get("changes", [])
        ),
    },
]


def analyze_agent_gaps(entries: list[dict]) -> dict:
    """Detect agents that should have been used but weren't."""
    gaps: Counter = Counter()
    gap_examples: dict[str, list[str]] = {}

    for entry in entries:
        actual = set(entry.get("agents_used", []))
        for rule in AGENT_RULES:
            if rule["match"](entry) and rule["agent"] not in actual:
                agent = rule["agent"]
                gaps[agent] += 1
                gap_examples.setdefault(agent, [])
                if len(gap_examples[agent]) < 5:
                    gap_examples[agent].append(entry.get("title", "?"))

    return {
        agent: {"missed": count, "examples": gap_examples.get(agent, [])}
        for agent, count in gaps.most_common()
    }


# ---------------------------------------------------------------------------
# Step 4: Effectiveness analysis
# ---------------------------------------------------------------------------

def analyze_effectiveness(entries: list[dict]) -> dict:
    """Analyze correlation between skill usage and error occurrence."""
    error_entries = [e for e in entries if e.get("errors")]
    no_error_entries = [e for e in entries if not e.get("errors")]

    error_tags: Counter = Counter()
    for entry in error_entries:
        for err in entry.get("errors", []):
            for tag in err.get("tags", []):
                error_tags[tag] += 1

    skills_with_errors: Counter = Counter()
    for entry in error_entries:
        for skill in entry.get("skills_used", []):
            skills_with_errors[skill] += 1

    effective_skills: Counter = Counter()
    for entry in no_error_entries:
        for skill in entry.get("skills_used", []):
            effective_skills[skill] += 1

    return {
        "total_entries": len(entries),
        "error_entries": len(error_entries),
        "repeated_error_tags": {t: c for t, c in error_tags.most_common() if c >= 2},
        "skills_with_errors": dict(skills_with_errors),
        "effective_skills": dict(effective_skills),
    }


# ---------------------------------------------------------------------------
# Cursor update
# ---------------------------------------------------------------------------

def update_cursor(log_base: Path, total: int, full_analysis: bool):
    """Write analyzed line number to cursor file."""
    (log_base / "self-improve").mkdir(parents=True, exist_ok=True)
    cursor_file = log_base / "self-improve/.cursor"
    cursor_file.write_text(str(total) + "\n")

    if full_analysis:
        last_full_file = log_base / "self-improve/.last-full"
        last_full_file.write_text(date.today().isoformat() + "\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse

    parser = argparse.ArgumentParser(description="log.jsonl self-improvement analysis")
    parser.add_argument("--log-base", help="Explicit log directory path")
    parser.add_argument("--update-cursor", action="store_true", help="Update cursor after analysis")
    args = parser.parse_args()

    log_base = Path(args.log_base) if args.log_base else resolve_log_base()
    status = check_status(log_base)

    if status["mode"] in ("no_log", "no_new"):
        print(json.dumps({"status": status}, indent=2, ensure_ascii=False))
        return

    entries = get_diff_entries(log_base, status["cursor"])
    all_resources = list_resources()

    result = {
        "status": status,
        "frequency": analyze_frequency(entries, all_resources),
        "all_resources": all_resources,
        "agent_gaps": analyze_agent_gaps(entries),
        "effectiveness": analyze_effectiveness(entries),
        "entries": [
            {
                "title": e.get("title"),
                "category": e.get("category"),
                "has_errors": bool(e.get("errors")),
                "skills_used": e.get("skills_used", []),
                "agents_used": e.get("agents_used", []),
                "learnings": e.get("learnings", []),
                "patterns": e.get("patterns", []),
            }
            for e in entries
        ],
    }

    print(json.dumps(result, indent=2, ensure_ascii=False))

    if args.update_cursor:
        update_cursor(log_base, status["total"], status["mode"] == "diff+full")
        print(f"\n# Cursor updated: {status['total']}", file=sys.stderr)


if __name__ == "__main__":
    main()
