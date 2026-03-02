---
name: qb-review-operations
description: "[Limited trigger] Triggered only for infrastructure, deployment, and monitoring configuration reviews. Targets: Dockerfile, k8s, CI/CD, monitoring config, operations docs. Not triggered for normal code reviews. SLO/SLA, availability, logging, incident response."
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: qb-review-operations]
```

---

# Operations Review Guide

Checklist for non-functional requirements and operational concerns.

---

## SLO / SLA

### Definitions

- [ ] Are SLIs (Service Level Indicators) defined?
- [ ] Are SLOs (Service Level Objectives) set?
- [ ] Is the error budget calculated?

### Key SLIs

| SLI          | Formula                         | Target Example |
| ------------ | ------------------------------- | -------------- |
| Availability | Successful requests / Total     | 99.9%          |
| Latency      | p99 response time               | < 500ms        |
| Throughput   | Requests/second                 | > 1000 RPS     |
| Error rate   | Errors / Total requests         | < 0.1%         |

### Error Budget

```
Monthly error budget (99.9% SLO):
43,200 min x 0.1% = 43.2 min/month
```

- [ ] Are actions defined for when error budget is consumed?
- [ ] Is there a release freeze when budget is exceeded?

---

## Availability & Reliability

### Failure Preparedness

- [ ] Are there no Single Points of Failure?
- [ ] Is a failover mechanism in place?
- [ ] Is Circuit Breaker implemented?
- [ ] Is Graceful Degradation designed?

### Redundancy

| Component    | Redundancy Method              |
| ------------ | ------------------------------ |
| Application  | Multiple instances + LB        |
| Database     | Primary-Replica                |
| Cache        | Cluster or replication         |
| Queue        | Cluster                        |

### Timeouts & Retries

- [ ] Are timeouts set for external communication?
- [ ] Is there a retry strategy (Exponential Backoff)?
- [ ] Is a retry limit set?
- [ ] Is Idempotency Key implemented?

---

## Monitoring & Observability

### Three Pillars

| Pillar  | Purpose             | Tool Examples         |
| ------- | ------------------- | --------------------- |
| Metrics | Time-series data    | Prometheus, Datadog   |
| Logs    | Event recording     | Loki, CloudWatch Logs |
| Traces  | Request tracking    | Jaeger, Tempo         |

### Metrics

- [ ] Are RED metrics (Rate, Errors, Duration) being measured?
- [ ] Are USE metrics (Utilization, Saturation, Errors) being measured?
- [ ] Are custom business metrics in place?

### Alerting

- [ ] Are alerting rules configured?
- [ ] Are alert severities (Critical, Warning, Info) classified?
- [ ] Is there an on-call rotation?
- [ ] Are alert fatigue countermeasures in place?

---

## Logging

### Log Levels

| Level | Usage                              |
| ----- | ---------------------------------- |
| ERROR | System errors, immediate action    |
| WARN  | Warnings, attention needed         |
| INFO  | Normal significant events          |
| DEBUG | Debug info (disabled in production)|

### Structured Logging

```json
{
  "timestamp": "2025-01-01T12:00:00Z",
  "level": "INFO",
  "message": "Order created",
  "orderId": "123",
  "userId": "456",
  "traceId": "abc-123"
}
```

### Checklist

- [ ] Are structured logs (JSON) used?
- [ ] Are trace IDs attached?
- [ ] Is sensitive information masked?
- [ ] Is log rotation configured?
- [ ] Is log retention period defined?

---

## Deployment Strategy

### Strategy Selection

| Strategy   | Risk | Rollback Speed | Use Case         |
| ---------- | ---- | -------------- | ---------------- |
| Blue-Green | Low  | Immediate      | High availability|
| Canary     | Low  | Immediate      | Gradual rollout  |
| Rolling    | Med  | Minutes        | General purpose  |
| Recreate   | High | Slow           | Dev environment  |

### Checklist

- [ ] Is the deployment strategy defined?
- [ ] Is the rollback procedure clear?
- [ ] Has rollback been tested?
- [ ] Are Feature Flags used?
- [ ] Are DB migrations forward-compatible?

### Zero-Downtime Deployment

- [ ] Can old and new versions coexist?
- [ ] Does the DB schema work with both versions?
- [ ] Is the API backward-compatible?

---

## Incident Response

### Incident Flow

```
Detection -> Triage -> Mitigation -> Root Cause Analysis -> Prevention
```

### Preparation

- [ ] Are Runbooks maintained?
- [ ] Is the escalation path clear?
- [ ] Is there an incident management tool?
- [ ] Are incident drills (Game Day) conducted?

### Troubleshooting

- [ ] Is it easy to identify the failure point?
- [ ] Can dependent service status be checked?
- [ ] Are health check endpoints available?

### Health Checks

```
/health       - Basic liveness check
/health/ready - Readiness including dependencies
/health/live  - Process liveness check
```

---

## Backup & Recovery

### RPO / RTO

| Metric | Meaning                      | Example |
| ------ | ---------------------------- | ------- |
| RPO    | Acceptable data loss period  | 1 hour  |
| RTO    | Acceptable downtime          | 4 hours |

### Checklist

- [ ] Are backups running on schedule?
- [ ] Has restore from backup been tested?
- [ ] Are backups in a different region/site?
- [ ] Is Point-in-Time Recovery available?

---

## Security Operations

See qb-review-security for details.

- [ ] Is secret rotation automated?
- [ ] Are vulnerability scans run regularly?
- [ ] Are dependency updates tracked?

---

## Cost

- [ ] Is resource sizing appropriate?
- [ ] Is auto-scaling configured?
- [ ] Are unused resources deleted?
- [ ] Are cost alerts set?

---

## Documentation

- [ ] Is the architecture diagram up to date?
- [ ] Are Runbooks maintained?
- [ ] Is there a dependency service list?
- [ ] Is there onboarding documentation?

---

## Output Format

```
## Operations Review Result
[LGTM / Needs Improvement / Needs Discussion]

## Check Results
| Category | Status | Notes |
|----------|--------|-------|
| SLO/SLA | OK/NG | ... |
| Availability | OK/NG | ... |
| Monitoring | OK/NG | ... |
| Logging | OK/NG | ... |
| Deployment | OK/NG | ... |
| Incident Response | OK/NG | ... |

## Issues Found
- Problem: [what is the issue]
- Risk: [impact if it occurs]
- Suggestion: [how to improve]
```

---

## References

- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)
- [The Art of SLOs](https://sre.google/resources/practices-and-processes/art-of-slos/)
