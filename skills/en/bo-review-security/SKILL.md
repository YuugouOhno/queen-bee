---
name: bo-review-security
description: "[Cross-cutting skill] Always triggered in pair with bo-review-backend/frontend/database during code reviews. Checks authentication, authorization, encryption, and input validation. OAuth 2.1, Zero Trust, mTLS, OWASP countermeasures."
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: bo-review-security]
```

---

# Security Review Guide

Security-focused review checklist.

---

## Authentication

### OAuth 2.1 Compliance

- [ ] Is PKCE (Proof Key for Code Exchange) used?
- [ ] Is exact Redirect URI matching enforced?
- [ ] Are deprecated grant types (Implicit, Password) not used?
- [ ] Are short-lived tokens + refresh tokens used?

### Token Management

| Item                       | Recommendation                          |
| -------------------------- | --------------------------------------- |
| Access token lifetime      | 15 min - 1 hour                         |
| Refresh token              | Rotation required                       |
| Storage                    | HttpOnly Cookie or Secure Storage       |
| Static API keys            | Avoid (use short-lived tokens)          |

### mTLS (Mutual TLS)

- [ ] Is mTLS used for service-to-service communication?
- [ ] Is client certificate verification performed?
- [ ] Is there a certificate rotation plan?

---

## Authorization

### Zero Trust Principles

> "Never trust, always verify"

- [ ] Is authorization checked on every request?
- [ ] Are requests from internal networks also verified?
- [ ] Is the principle of least privilege followed?

### RBAC / ABAC

- [ ] Is there role-based or attribute-based access control?
- [ ] Is there resource-level authorization (BOLA prevention)?
- [ ] Is authorization logic centralized?

### OWASP API Security Top 10 Countermeasures

| Threat                                      | Countermeasure                       |
| ------------------------------------------- | ------------------------------------ |
| BOLA (Broken Object Level Authorization)    | Owner check per resource             |
| BFLA (Broken Function Level Authorization)  | Permission check per endpoint        |
| Excessive Data Exposure                     | Return minimum necessary data only   |
| Mass Assignment                             | Accept only permitted fields         |

---

## Encryption

### In-Transit Encryption

- [ ] Is TLS 1.3 used?
- [ ] Is TLS 1.2 and below disabled?
- [ ] Is the HSTS header set?

### At-Rest Encryption

- [ ] Are passwords hashed with bcrypt/Argon2?
- [ ] Is sensitive data encrypted with AES-256?
- [ ] Are encryption keys managed securely (KMS, etc.)?

### Secret Management

- [ ] Are secrets not hardcoded in source code?
- [ ] Are environment variables or Secret Manager used?
- [ ] Is there a secret rotation plan?

---

## Input Validation

### Validation

- [ ] Is all external input validated server-side?
- [ ] Are type, length, format, and range checked?
- [ ] Is an allowlist approach adopted?

### Injection Prevention

| Attack            | Countermeasure                |
| ----------------- | ----------------------------- |
| SQL Injection     | Parameterized queries         |
| NoSQL Injection   | Input type checking, sanitize |
| XSS               | Output escaping, CSP          |
| Command Injection | Avoid shell invocations       |

### Rate Limiting

- [ ] Are rate limits set on APIs?
- [ ] Is there brute force attack prevention?
- [ ] Is there DDoS protection (WAF, CDN)?

---

## Logging & Monitoring

### Security Logging

- [ ] Are authentication successes/failures logged?
- [ ] Are authorization failures logged?
- [ ] Is sensitive information excluded from logs?

### Anomaly Detection

- [ ] Can abnormal access patterns be detected?
- [ ] Are alerting rules configured?
- [ ] Are incident response procedures in place?

---

## AI Threat Detection (Current Trends)

- [ ] Has AI/ML-based anomaly detection been considered?
- [ ] Is API behavior analysis in place?
- [ ] Is automated threat response available?

---

## Final Checklist

- [ ] Has each item of OWASP Top 10 been verified?
- [ ] Has penetration testing been conducted?
- [ ] Has a security review been performed?

---

## Output Format

```
## Security Review Result
[LGTM / Needs Changes / Needs Discussion]

## Check Results
| Category | Status | Notes |
|----------|--------|-------|
| Authentication | OK/NG | ... |
| Authorization | OK/NG | ... |
| Encryption | OK/NG | ... |
| Input Validation | OK/NG | ... |
| Logging & Monitoring | OK/NG | ... |

## Issues Found
- Threat: [what is the issue]
- Risk: [High/Medium/Low]
- Countermeasure: [how to fix]
```

---

## Financial Security (Additional)

Additional checks for critical transactions involving finance, payments, points, etc.

See `references/finance-security.md` for details.

### Race Condition Prevention

- [ ] Is optimistic locking (version column) used?
- [ ] Is pessimistic locking (SELECT FOR UPDATE) used appropriately?
- [ ] Have concurrent request tests been conducted?

### Transaction Integrity

- [ ] Are critical operations executed within transactions?
- [ ] Is the transaction isolation level appropriate?
- [ ] Are partial commits prevented?

### Idempotency (Double Processing Prevention)

- [ ] Is an Idempotency Key used?
- [ ] Is double processing prevented on retry?
- [ ] Is there a duplicate request check?

### Enhanced Session Management

- [ ] Is there session fixation attack prevention?
- [ ] Is concurrent login control in place?
- [ ] Is re-authentication required for high-risk operations?

---

## References

- [OWASP API Security Top 10](https://owasp.org/API-Security/)
- [OAuth 2.1 Draft](https://oauth.net/2.1/)
- [Zero Trust Architecture (NIST)](https://www.nist.gov/publications/zero-trust-architecture)
- `references/finance-security.md` - Financial security details
