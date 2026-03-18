---
name: bee-review-process
description: "[Meta skill] Triggered only for review process quality questions and improvements. Targets: PR writing, comment conventions, review team structure and rules. Not triggered during actual code reviews."
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: bee-review-process]
```

---

# Code Review Process Guide

Defines the process and rules for code reviews.

---

## Core Principles

### PR Size

| Size | Lines       | Verdict              |
| ---- | ----------- | -------------------- |
| S    | up to 200   | Ideal                |
| M    | 201-400     | Acceptable           |
| L    | over 400    | Consider splitting   |

**Splitting principle**: 1 PR = 1 logical change. Separate refactoring from feature additions.

### Human vs Automation

| Automation                          | Human Review                     |
| ----------------------------------- | -------------------------------- |
| Formatting, Lint, type checking     | Design & architecture            |
| Security scanning, test execution   | Business logic correctness       |
| Coverage checks                     | Naming, readability, edge cases  |

---

## Comment Classification

| Prefix     | Meaning          | Action                   |
| ---------- | ---------------- | ------------------------ |
| `[MUST]`   | Required fix     | Must address before merge|
| `[SHOULD]` | Recommended      | Author's judgment        |
| `[NIT]`    | Minor issue      | Optional to address      |
| `[Q]`      | Question         | Reply required           |

**Principle**: Criticize the code, not the person. Explain "why" and suggest alternatives.

---

## Checklists

### Reviewer

- [ ] Do I understand the purpose of the PR?
- [ ] Is the change scope appropriate (scope creep)?
- [ ] Are tests sufficient?
- [ ] Does documentation need updating?
- [ ] Are there breaking changes?
- [ ] Are there security concerns?

**Time allocation guide**:

| Phase              | Time Ratio |
| ------------------ | ---------- |
| Understanding overview | 10%    |
| Code review        | 60%        |
| Test verification  | 20%        |
| Writing comments   | 10%        |

### Author (Before PR creation)

- [ ] Performed self-review?
- [ ] CI is passing?
- [ ] PR description is sufficient?
- [ ] Related Issue/ticket is linked?
- [ ] Screenshots attached (for UI changes)?

**PR description template**:

```markdown
## Summary

[What changed and why]

## Changes

- [Change 1]
- [Change 2]

## Test Plan

- [Verification steps]

## Related

- Closes #123
```

---

## Review Anti-Patterns

Patterns where reviews become dysfunctional. Correct these when detected.

### Excessive Comments

**Symptom**: More than 10 comments on a single PR

| Cause                    | Fix                        |
| ------------------------ | -------------------------- |
| PR is too large          | Ask to split the PR        |
| Requirements were vague  | Do design review first     |
| No coding conventions    | Solve with automation      |

**Rule**: If > 10 comments, suggest PR split

### Preference Reviews

**Symptom**: "I would write it this way" proliferates

| Identification        | Response                         |
| --------------------- | -------------------------------- |
| No impact on behavior | Tag as [NIT], make optional      |
| Not in conventions    | Add to conventions or let it go  |
| Affects readability   | Explain reasoning, use [SHOULD]  |

**Rule**: Distinguish "preference" from "quality"

### Unresolved Spec Reviews

**Symptom**: "Should this feature even..." appears in comments

| Cause                     | Fix                          |
| ------------------------- | ---------------------------- |
| Skipped design review     | Close PR, start from design  |
| Requirements changed      | Close PR, redesign           |

**Rule**: Don't do design discussions in PR reviews

### Rubber Stamp Approvals

**Symptom**: "LGTM" only, instant approval

| Cause                | Fix                          |
| -------------------- | ---------------------------- |
| No time for review   | Adjust team workload         |
| Too much trust       | Random detailed reviews      |

**Rule**: Ask at least one question even if nothing found

### Blocking Reviews

**Symptom**: Review abandoned for 48+ hours

| Cause                | Fix                     |
| -------------------- | ----------------------- |
| Reviewer is busy     | Assign multiple reviewers|
| PR is too complex    | Request pair review      |

**Rule**: Escalate after 48 hours

### Emotional Reviews

**Symptom**: Aggressive or sarcastic comments

**Response**: Intervene immediately. Edit or delete comment. Give feedback in 1-on-1.

**Rule**: Criticize the code, not the person

---

## References

- [Google Engineering Practices](https://google.github.io/eng-practices/review/)
