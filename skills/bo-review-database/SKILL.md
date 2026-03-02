---
name: qb-review-database
description: Triggered for DB schema, query, and migration reviews. [Required pair: qb-review-security] Targets: SQL, ORM schema definitions, DB design docs (doc/design/database). PostgreSQL-centric.
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: qb-review-database]
```

---

# Database Review Guide

Checklist for reviewing database design and queries.

---

## Schema Design

### Table Design

- [ ] Are table names clear and consistent (snake_case, plural recommended)?
- [ ] Are primary keys properly set (UUID v7 recommended)?
- [ ] Are foreign key constraints set?
- [ ] Is the normalization level appropriate?

| Normalization | Criteria                        |
| ------------- | ------------------------------- |
| 3NF           | Default (most cases)            |
| Denormalized  | Only when read performance is critical |

### Column Design

- [ ] Are column names semantically clear?
- [ ] Are data types appropriate?

| Use Case  | Recommended Type (PostgreSQL) |
| --------- | ----------------------------- |
| ID        | UUID (v7)                     |
| Money     | DECIMAL / NUMERIC             |
| Datetime  | TIMESTAMPTZ                   |
| JSON      | JSONB (not JSON)              |
| Text      | TEXT (VARCHAR unnecessary)     |
| Enum      | ENUM or CHECK constraint      |

- [ ] Is NULL allowance appropriate (default NOT NULL)?
- [ ] Are default values set?

### Constraints

- [ ] Are UNIQUE constraints set where needed?
- [ ] Are CHECK constraints enforcing data integrity?
- [ ] Are CASCADE delete/update settings appropriate?

### Audit Columns

- [ ] Are `created_at` / `updated_at` present?
- [ ] Are `created_by` / `updated_by` present if needed?
- [ ] Is `deleted_at` present for soft deletes?

---

## Index Design

### Index Selection

- [ ] Are columns frequently used in WHERE clauses indexed?
- [ ] Are JOIN condition columns indexed?
- [ ] Have columns used in ORDER BY / GROUP BY been considered?
- [ ] Are foreign keys indexed?

### Index Types (PostgreSQL)

| Type   | Use Case                   |
| ------ | -------------------------- |
| B-tree | General purpose (default)  |
| Hash   | Equality comparisons only  |
| GIN    | Arrays, JSONB, full-text search |
| GiST   | Geographic, range          |
| BRIN   | Large data, time-series    |

### Composite Indexes

- [ ] Is column order appropriate (highest selectivity first)?
- [ ] Has cardinality been considered?
- [ ] Has a covering index been considered?

### Cautions

- [ ] Are there unnecessary indexes (impact on write performance)?
- [ ] Has a partial index been considered?
- [ ] Should the index be created CONCURRENTLY?

---

## Query Optimization

### SELECT

- [ ] Is SELECT \* avoided?
- [ ] Are only necessary columns fetched?
- [ ] Is LIMIT used to restrict result count?

### JOIN

- [ ] Are JOIN conditions appropriate?
- [ ] Are there unnecessary JOINs?
- [ ] Is JOIN order optimal (start from smaller tables)?

### N+1 Problem

- [ ] Are queries being issued inside loops?
- [ ] Is necessary data fetched in bulk upfront?
- [ ] Is Eager Loading / Batch Loading used?

### Subqueries

- [ ] Has replacing subqueries with JOINs been considered?
- [ ] Are correlated subqueries avoided?
- [ ] Is the choice between EXISTS and IN appropriate (EXISTS is usually faster)?

### EXPLAIN

- [ ] Has the execution plan (EXPLAIN ANALYZE) been checked?
- [ ] Has the absence of Seq Scan been verified?
- [ ] Is there a discrepancy between estimated and actual row counts?

---

## Migrations

### Safe Migrations

- [ ] Can the migration be applied without downtime?
- [ ] Is a rollback procedure prepared?
- [ ] Has the impact on large datasets been considered?

### Expand and Contract Pattern

| Phase    | Description                          |
| -------- | ------------------------------------ |
| Expand   | Add new structure (maintain compatibility) |
| Migrate  | Move data to new structure           |
| Contract | Remove old structure                 |

### Safe Changes

| Change        | Safe Method                                    |
| ------------- | ---------------------------------------------- |
| Add column    | NULL-allowed or with default value             |
| Drop column   | Stop using first, drop later                   |
| Rename column | Add new column -> migrate data -> drop old     |
| Type change   | Add new column -> convert data -> swap         |

### Large Data Handling

- [ ] Is batch processing used?
- [ ] Can progress be checked and resumed?
- [ ] Is lock time minimized?

---

## Data Integrity

### Transactions

- [ ] Are transaction boundaries appropriate?
- [ ] Is the isolation level appropriate?

| Isolation Level | Use Case                        |
| --------------- | ------------------------------- |
| READ COMMITTED  | General purpose (PostgreSQL default) |
| REPEATABLE READ | Reports, aggregations           |
| SERIALIZABLE    | Financial transactions, strict consistency |

- [ ] Has deadlock risk been considered?
- [ ] Is the choice between optimistic and pessimistic locking appropriate?

### Referential Integrity

- [ ] Are foreign key constraints appropriate?
- [ ] Is the choice between soft and hard deletes appropriate?

---

## Performance Monitoring

- [ ] Is pg_stat_statements enabled?
- [ ] Is slow query logging configured?
- [ ] Are statistics up to date (ANALYZE)?
- [ ] Is connection pooling properly configured?

### Recommended Tools

| Tool               | Use Case          |
| ------------------ | ----------------- |
| EXPLAIN ANALYZE    | Query analysis    |
| pg_stat_statements | Query statistics  |
| pgMustard          | Plan visualization|
| pgBadger           | Log analysis      |

---

## Migration Management

- [ ] Is a migration tool (Flyway, Prisma, etc.) being used?
- [ ] Are migrations version-controlled?
- [ ] Are rollback migrations available?

---

## Output Format

```
## Database Review Result
[LGTM / Needs Changes / Needs Discussion]

## Check Results
| Category | Status | Notes |
|----------|--------|-------|
| Schema Design | OK/NG | ... |
| Indexes | OK/NG | ... |
| Query Optimization | OK/NG | ... |
| Migrations | OK/NG | ... |
| Data Integrity | OK/NG | ... |

## Issues Found
- Problem: [what is the issue]
- Location: [table name / query]
- Suggestion: [how to fix]
```

---

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/current/)
- [Use The Index, Luke](https://use-the-index-luke.com/)
- [pgMustard](https://www.pgmustard.com/)
