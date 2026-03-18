---
name: bee-review-backend
description: Triggered for backend code and API design reviews, INCLUDING after bugfixes and implementation changes. [Required pair: bee-review-security] Auto-trigger after any implementation/bugfix to server-side code (.ts/.js/.py etc., including CLI scripts like bin/*.js), API design docs (doc/design/api), domain models. Use bee-review-frontend for frontend, bee-review-database for DB.
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: bee-review-backend]
```

---

# Backend Review Guide

Checklist for reviewing backend code.

---

## API Design

### RESTful Design

- [ ] Are resource names nouns in plural form (`/users`, `/orders`)?
- [ ] Are HTTP methods used appropriately?

| Method | Purpose      | Idempotent |
| ------ | ------------ | ---------- |
| GET    | Retrieve     | Yes        |
| POST   | Create       | No         |
| PUT    | Full update  | Yes        |
| PATCH  | Partial update | Yes      |
| DELETE | Delete       | Yes        |

### Status Codes

| Code | Usage                     |
| ---- | ------------------------- |
| 200  | Success                   |
| 201  | Created                   |
| 204  | Success (no content)      |
| 400  | Bad request               |
| 401  | Authentication error      |
| 403  | Authorization error       |
| 404  | Resource not found        |
| 409  | Conflict                  |
| 422  | Validation error          |
| 429  | Rate limited              |
| 500  | Server error              |

### Endpoint Design

- [ ] Does the URL express hierarchical structure (`/users/:id/orders`)?
- [ ] Are query parameters used appropriately (filtering, sorting, pagination)?
- [ ] Is the versioning strategy clear (`/v1/users` or Header)?

### Response Design

- [ ] Does it return only the minimum necessary data (Excessive Data Exposure prevention)?
- [ ] Is pagination implemented (cursor-based recommended)?
- [ ] Is the response format consistent?

```json
{
  "data": { ... },
  "meta": { "page": 1, "total": 100 },
  "errors": []
}
```

---

## Domain Model

### Entity Design

- [ ] Do entities accurately represent business concepts?
- [ ] Is the ID generation strategy appropriate (UUID v7 recommended)?
- [ ] Are invariants maintained?

### Value Objects

- [ ] Are business concepts expressed using primitive types inappropriately?
- [ ] Are value objects immutable?
- [ ] Is equality determined by value?

```typescript
// Bad: primitives
function processOrder(userId: string, amount: number) {}

// Good: value objects
function processOrder(userId: UserId, amount: Money) {}
```

### Domain Logic

- [ ] Is business logic consolidated in domain objects?
- [ ] Is logic leaking into the service layer?
- [ ] Are business rules expressed as collections of if/switch statements?

---

## Error Handling

### Error Classification

| Type           | Example              | Response                |
| -------------- | -------------------- | ----------------------- |
| Business error | Out of stock         | Notify user             |
| Technical error| DB connection failed | Retry + alert           |
| Input error    | Validation failed    | Return details          |

### Exception Handling

- [ ] Are exceptions caught at the appropriate layer?
- [ ] Are there swallowed exceptions (catch with no action)?
- [ ] Are retryable errors distinguished?

### Error Response

```json
{
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Insufficient balance",
    "details": { "required": 1000, "available": 500 }
  }
}
```

- [ ] Are technical details (stack traces, etc.) not exposed?
- [ ] Are error codes systematic?

---

## Performance

### Database

- [ ] Are there N+1 query problems?
- [ ] Are appropriate indexes set?
- [ ] Is unnecessary data being fetched (avoid SELECT \*)?
- [ ] Is cursor-based pagination used for large datasets?

### Caching

- [ ] Has a caching strategy been considered?
- [ ] Is cache invalidation handled properly?
- [ ] Are cache keys appropriate?

| Strategy      | Use case                   |
| ------------- | -------------------------- |
| Cache-Aside   | General purpose            |
| Write-Through | Write consistency priority |
| Write-Behind  | Write performance priority |

### Async Processing

- [ ] Are heavy operations made asynchronous?
- [ ] Are timeouts configured?
- [ ] Is concurrency control appropriate?
- [ ] Is there a retry strategy (Exponential Backoff)?

---

## Testing

### Unit Tests

- [ ] Is domain logic tested?
- [ ] Are boundary values tested?
- [ ] Are error cases tested?

### Integration Tests

- [ ] Are API endpoints tested?
- [ ] Are external services mocked?
- [ ] Is database integration tested?

### Test Quality

- [ ] Can tests be read as specifications?
- [ ] Are tests tightly coupled to implementation details?
- [ ] Is coverage of critical paths prioritized over raw coverage numbers?

### Cross-Platform Compatibility (Node.js CLI / package.json scripts)

- [ ] Does `package.json` `test` script use a glob pattern? If so, verify it works on **Linux CI** (not just macOS/zsh).
  - `node --test 'test/**/*.test.js'` fails on Linux because the shell does not expand single-quoted globs
  - Fix: pass a literal path (`node --test test/cli.test.js`) or use a glob library (`glob` npm package or `--test-reporter` options)
  - Root cause: macOS/zsh expands globs before passing to node, Linux/sh does not

---

## Code Quality

- [ ] Is Dependency Injection (DI) used appropriately?
- [ ] Are interfaces and implementations separated?
- [ ] Are transaction boundaries appropriate?
- [ ] Is resource cleanup ensured (DB connections, file handles)?

---

## Anti-Pattern Detection

- [ ] Is there business logic in controllers?
- [ ] Is there domain logic in repositories?
- [ ] Are there god classes (classes that do everything)?
- [ ] Are there circular dependencies?

---

## Output Format

```
## Backend Review Result
[LGTM / Needs Changes / Needs Discussion]

## Check Results
| Category | Status | Notes |
|----------|--------|-------|
| API Design | OK/NG | ... |
| Domain Model | OK/NG | ... |
| Error Handling | OK/NG | ... |
| Performance | OK/NG | ... |
| Testing | OK/NG | ... |

## Issues Found
- Problem: [what is the issue]
- Location: [file:line_number]
- Suggestion: [how to fix]
```
