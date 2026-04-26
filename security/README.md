# Security — claudeforge guides

> Pre-launch checklist, threat modeling, secrets, common vulnerabilities. Not a security cert curriculum — the practical "what to verify before going live" cuts.

## Files

| File | What it is |
|------|-----------|
| [`security-review-checklist.md`](./security-review-checklist.md) | Pre-launch checklist — auth, transport, storage, dependencies, deployment |
| [`threat-modeling.md`](./threat-modeling.md) | Lightweight STRIDE — how to think about what could go wrong |
| [`secrets-management.md`](./secrets-management.md) | Where secrets live, how to rotate, how to detect leaks |
| [`owasp-top-10-quickref.md`](./owasp-top-10-quickref.md) | OWASP 10 mapped to the claudeforge stack — defenses per layer |

## Companion

For CI-side secret handling: [`cicd/secrets-and-environments.md`](../cicd/secrets-and-environments.md).

For per-framework auth patterns: `backend/{fastapi,nestjs,nodejs-express}/04-auth-*.md`.

## Quick decision summary

- **Always-on**: HTTPS, security headers (HSTS, CSP, X-Frame-Options), httpOnly cookies, parameterized queries, OWASP-tier dependency updates.
- **Before launch**: run the security review checklist (`security-review-checklist.md`) end-to-end.
- **Quarterly**: rotate secrets, review dependency CVEs, review IAM access lists.
- **Per feature**: think about what changes (new attack surface, new data, new permissions). Light STRIDE pass.
- **Per incident**: write a postmortem; add a regression test or eval.

## Anti-patterns rejected

- "Security is a phase at the end" — bake it in
- Disabling SSL verification "just for now"
- "We'll fix that vuln after launch" — for high-severity, you won't
- Sharing prod credentials in Slack
- Long-lived AWS / GCP keys in CI (use OIDC)
- Custom crypto (use a real library)
- "It's only an internal tool" — internal tools are still attack vectors
