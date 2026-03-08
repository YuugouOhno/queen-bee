#!/usr/bin/env python3
"""Inject context based on environment variables (UserPromptSubmit hook).

Reads agent-modes.json to determine the active mode, then outputs the
corresponding context file content.

Context resolution order (4-step fallback):
  1. Project local (locale): <project>/.claude/beeops/contexts/<locale>/<file>
  2. Project local (root):   <project>/.claude/beeops/contexts/<file>
  3. Package (locale):        <pkg>/contexts/<locale>/<file>
  4. Package (root):          <pkg>/contexts/<file>

Locale is determined by BO_LOCALE env var (default: "en").
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

PKG_CONTEXT_DIR = Path(__file__).resolve().parent.parent / "contexts"
DEFAULT_LOCALE = "en"


def get_project_root() -> Optional[Path]:
    """Get project root via git rev-parse. Returns None on failure."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def get_locale(root: Optional[Path]) -> str:
    """Get locale from BO_LOCALE env var or .claude/beeops/locale file."""
    env_locale = os.environ.get("BO_LOCALE")
    if env_locale:
        return env_locale
    if root:
        locale_file = root / ".claude" / "beeops" / "locale"
        if locale_file.is_file():
            return locale_file.read_text().strip() or DEFAULT_LOCALE
    return DEFAULT_LOCALE


def get_local_context_dir(root: Optional[Path]) -> Optional[Path]:
    """Return project-local contexts directory if it exists."""
    if root is None:
        return None
    local_dir = root / ".claude" / "beeops" / "contexts"
    return local_dir if local_dir.is_dir() else None


def resolve_file(filename: str, local_dir: Optional[Path], locale: str) -> Optional[Path]:
    """Resolve a context file with 4-step locale fallback."""
    candidates = []

    # 1. Project local (locale-specific)
    if local_dir:
        candidates.append(local_dir / locale / filename)
    # 2. Project local (root)
    if local_dir:
        candidates.append(local_dir / filename)
    # 3. Package (locale-specific)
    candidates.append(PKG_CONTEXT_DIR / locale / filename)
    # 4. Package (root)
    candidates.append(PKG_CONTEXT_DIR / filename)

    for path in candidates:
        if path.is_file():
            return path
    return None


def load_modes(local_dir: Optional[Path], locale: str) -> dict:
    """Load agent-modes.json with locale fallback."""
    modes_path = resolve_file("agent-modes.json", local_dir, locale)
    if modes_path:
        return json.loads(modes_path.read_text())
    return {"modes": {}, "default_context": "default.md"}


def main():
    root = get_project_root()
    locale = get_locale(root)
    local_dir = get_local_context_dir(root)
    config = load_modes(local_dir, locale)
    modes = config.get("modes", {})

    # Detect active modes (non-append modes take priority)
    primary_contexts = []
    append_contexts = []

    for env_var, mode_conf in modes.items():
        if os.environ.get(env_var) != "1":
            continue
        context_files = mode_conf.get("context", [])
        if mode_conf.get("append"):
            append_contexts.extend(context_files)
        else:
            primary_contexts.extend(context_files)

    # If any mode is active, output its context
    if primary_contexts or append_contexts:
        for ctx_file in primary_contexts:
            resolved = resolve_file(ctx_file, local_dir, locale)
            if resolved:
                print(resolved.read_text().strip())

        for ctx_file in append_contexts:
            resolved = resolve_file(ctx_file, local_dir, locale)
            if resolved:
                print("\n---\n")
                print(resolved.read_text().strip())
    else:
        # Default context
        default_name = config.get("default_context", "default.md")
        default_path = resolve_file(default_name, local_dir, locale)
        if default_path:
            print(default_path.read_text().strip())

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"[HOOK ERROR] prompt-context.py: {e}", file=sys.stderr)
        sys.exit(0)
