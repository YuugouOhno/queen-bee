---
name: bee-issue-sync
description: Sync GitHub Issues to queue.yaml. Detects new issues, analyzes dependencies, assigns priorities, and performs diff-merge.
---

# bee-issue-sync: Issue → queue.yaml Sync

Fetches open Issues from GitHub and syncs them to `.beeops/tasks/queue.yaml`.
Handles adding new Issues, marking closed Issues as done, dependency analysis, and priority assignment in one operation.

## Procedure

### 1. Determine Repository

```bash
REPO=$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
```

Use `-R $REPO` for all subsequent `gh` commands.

### 2. Fetch Open Issues

```bash
gh issue list -R "$REPO" --state open --json number,title,labels,assignees --limit 100
```

If 0 issues, display "No issues to process" and exit.

### 2.5. Detect Existing PRs

For each open Issue, check if a linked PR already exists:

```bash
gh pr list -R "$REPO" --search "linked:issue:{number}" --state open --json number,url,headRefName --limit 1
```

If no result, also try keyword search as fallback:

```bash
gh pr list -R "$REPO" --search "{issue_number} in:title" --state open --json number,url,headRefName --limit 1
```

Store the results (PR URL + branch name) for use in Step 4.

### 3. Load queue.yaml

If `.beeops/tasks/queue.yaml` exists, read it. Otherwise initialize:

```yaml
version: 1
tasks: []
```

### 4. Diff Detection and Raw Addition

Add Issues not present in queue.yaml. If an existing PR was detected in Step 2.5, start from `review_dispatched`; otherwise use `raw` status:

**No existing PR (normal flow):**

```yaml
- id: "ISSUE-{number}"
  issue: {number}
  title: "{title}"
  status: raw
  priority: null
  branch: null
  depends_on: []
  review_count: 0
  pr: null
  log:
    - "{ISO8601} created from gh issue"
```

**Existing PR detected (skip to review):**

```yaml
- id: "ISSUE-{number}"
  issue: {number}
  title: "{title}"
  status: review_dispatched
  priority: high
  branch: "{headRefName from PR}"
  depends_on: []
  review_count: 0
  pr: "{PR URL}"
  log:
    - "{ISO8601} created from gh issue (existing PR #{pr_number} detected, starting from review)"
```

- Skip Issues already in queue.yaml (with status other than done)
- Update status to `done` for Issues in queue.yaml that are closed on GitHub

### 5. Dependency Analysis

For each `raw` Issue:

1. Fetch details: `gh issue view {N} -R "$REPO" --json body,labels`
2. Determine dependencies:
   - Issue body mentions "depends on #XX", "blocked by #XX", "after #XX", etc.
   - Labels include `blocked`, `pending`, etc.
   - Likely modifies the same files as other implementing/queued tasks (inferred from body)
3. Add task IDs to `depends_on` if dependencies exist
4. For issues with `pending` label, extract `blocked_reason` from the issue body

### 6. Priority Assignment and Queued Status

Set priority for each `raw` task and update to `queued`:

| Condition | Priority |
|-----------|----------|
| Labels include `priority: high`, `urgent`, `bug` | high |
| Normal feature additions/improvements, `priority: medium` | medium |
| Labels include `priority: low`, `tech-debt` | low |

**Branch name generation**: Derive from Issue title with `feat/`, `fix/`, `chore/` prefix + kebab-case

### 7. Write queue.yaml

```bash
mkdir -p .beeops/tasks
```

Write `.beeops/tasks/queue.yaml` using the Write tool.

### 8. Display Status

```
=== Queue Status ===
Repository: {REPO}
Total: {N} tasks

[HIGH] Ready to start:
  ISSUE-42  Add user authentication    queued  branch: feat/add-user-auth

[BLOCKED] External blockers:
  ISSUE-55  Database migration v2      queued  → Waiting for staging deploy
```
