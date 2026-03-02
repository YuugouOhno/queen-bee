---
name: qb-review-frontend
description: Triggered for frontend code and component design reviews. [Required pair: qb-review-security] Targets: React/Vue etc. (.tsx/.vue), frontend design docs (doc/design/frontend). Use qb-review-backend for backend, qb-review-database for DB.
---

## Usage Contract

When using this skill, always include the following at the beginning of your output:

```
[SKILL_USED: qb-review-frontend]
```

---

# Frontend Review Guide

Checklist for reviewing frontend code.

---

## Component Design

### Separation of Concerns

- [ ] Does each component have a single responsibility?
- [ ] Is business logic leaking into UI components?
- [ ] Is the separation of Server Components and Client Components appropriate?

### Component Size

- [ ] Have components exceeding 100 lines been considered for splitting?
- [ ] If props exceed 5, has the design been reconsidered?
- [ ] Is there logic that should be extracted into custom hooks?

### Props Design

- [ ] Are required/optional props clearly defined?
- [ ] Are default values appropriate?
- [ ] Are type definitions accurate (TypeScript)?
- [ ] Is prop drilling avoided?

---

## State Management

### State Placement

| State Type        | Placement             |
| ----------------- | --------------------- |
| Local UI state    | useState              |
| Shared UI state   | Context / Zustand     |
| Server state      | TanStack Query / SWR  |
| URL state         | Router                |
| Form state        | React Hook Form       |

- [ ] Is state placed at the minimum necessary scope?
- [ ] Are unnecessary global states being created?
- [ ] Is derived state being held as state?

### State Updates

- [ ] Is immutability maintained?
- [ ] Is the state update logic clear?
- [ ] Is there a possibility of infinite loops?

### Side Effects

- [ ] Is the useEffect dependency array accurate?
- [ ] Are cleanup functions implemented as needed?
- [ ] Is useEffect being overused (React 19 optimizes with compiler)?

---

## Performance (Core Web Vitals)

### Target Values

| Metric | Target  | Description               |
| ------ | ------- | ------------------------- |
| LCP    | < 2.5s  | Largest Contentful Paint  |
| INP    | < 200ms | Interaction to Next Paint |
| CLS    | < 0.1   | Cumulative Layout Shift   |
| FCP    | < 1.8s  | First Contentful Paint    |

### High-Impact Optimizations (Priority)

- [ ] Is React Compiler being used (React 19+)?
- [ ] Is Code Splitting / Lazy Loading applied?
- [ ] Are images optimized (next/image, etc.)?
- [ ] Is the state management architecture appropriate?

### Rendering Optimization

- [ ] Are unnecessary re-renders prevented?
- [ ] Are React.memo / useMemo / useCallback used **only when necessary**?
  - With React 19 + Compiler, auto-memoization makes these unnecessary in many cases
- [ ] Are expensive computations memoized?

### Bundle Size

- [ ] Are there unnecessary dependencies?
- [ ] Are imports tree-shakeable?
- [ ] Is Dynamic Import being used?

### List Optimization

- [ ] Has virtualization (react-window, etc.) been considered for long lists?
- [ ] Are keys properly set (avoid index)?

---

## Accessibility (WCAG 2.2)

### Semantics

- [ ] Are appropriate HTML elements used (avoid div soup)?
- [ ] Are heading levels (h1-h6) appropriate?
- [ ] Are landmark elements (nav, main, aside, etc.) used?
- [ ] Are buttons using `<button>` (not div + onClick)?

### Keyboard Operation

- [ ] Are all interactive elements keyboard-accessible?
- [ ] Is the focus order logical?
- [ ] Is the focus state visually clear?
- [ ] Are focus traps (modals, etc.) appropriate?

### Screen Reader

- [ ] Do images have alt attributes?
- [ ] Do icon buttons have aria-label?
- [ ] Are dynamic content updates announced (aria-live)?
- [ ] Are form inputs associated with labels?

### Contrast & Color

- [ ] Is text contrast ratio 4.5:1 or higher?
- [ ] Is large text (18pt+) 3:1 or higher?
- [ ] Is information conveyed through color alone avoided?

### Motion

- [ ] Is `prefers-reduced-motion` respected?
- [ ] Can auto-playing animations be stopped?

---

## Error Handling

- [ ] Are API errors handled appropriately?
- [ ] Are user-friendly error messages displayed?
- [ ] Are Error Boundaries configured?
- [ ] Are loading states displayed?
- [ ] Is Suspense used appropriately?

---

## Testing

### Test Perspectives

- [ ] Are critical user flows tested?
- [ ] Is component behavior tested?
- [ ] Are tests written from the user's perspective, not implementation details?
- [ ] Are edge cases considered?

### Testing Library

```typescript
// Good: user perspective
screen.getByRole('button', { name: 'Submit' });

// Bad: implementation details
container.querySelector('.submit-btn');
```

### Test Quality

- [ ] Can tests be read as specifications?
- [ ] Are tests tightly coupled to implementation details?
- [ ] Has Visual Regression Testing been considered?

---

## Security

- [ ] XSS prevention: is dangerouslySetInnerHTML avoided?
- [ ] Is user input sanitized?
- [ ] Is sensitive information not exposed to the client?
- [ ] Is HTTPS used?
- [ ] Is CSP (Content Security Policy) configured?

---

## Build Tools

| Tool      | Use Case                      |
| --------- | ----------------------------- |
| Vite      | Dev server, build             |
| Turbopack | Fast build for Next.js        |
| Bun       | Runtime + build               |

- [ ] Is build time within acceptable range?
- [ ] Does HMR work properly?

---

## Output Format

```
## Frontend Review Result
[LGTM / Needs Changes / Needs Discussion]

## Check Results
| Category | Status | Notes |
|----------|--------|-------|
| Component Design | OK/NG | ... |
| State Management | OK/NG | ... |
| Performance | OK/NG | ... |
| Accessibility | OK/NG | ... |
| Testing | OK/NG | ... |

## Issues Found
- Problem: [what is the issue]
- Location: [file:line_number]
- Suggestion: [how to fix]
```

---

## References

- [React Best Practices 2025](https://talent500.com/blog/modern-frontend-best-practices-with-react-and-next-js-2025/)
- [Web Vitals](https://web.dev/vitals/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
