# OWASP Top 10 — claudeforge stack quick reference

> Map each OWASP Top 10 (2021 edition) to defenses in the claudeforge stack. Quick reference, not a curriculum.

## A01:2021 — Broken Access Control

**The risk**: users can access data or actions they shouldn't.

**Common forms**: IDOR (`GET /orders/123` returns someone else's order), missing function-level auth (admin endpoint not behind admin guard), forced browsing.

**Defenses in this stack**:
- Default-deny global guard (FastAPI `CurrentUser` dep, NestJS global `JwtAuthGuard` + `@Public` opt-out)
- Resource-level checks in services (`if order.user_id != actor.id: raise Forbidden`)
- Multi-tenant filter on every query (or RLS in Postgres)
- Use route IDs that aren't enumerable (UUIDs, not auto-int)

References: `backend/{fastapi,nestjs,nodejs-express}/04-auth-*.md`

## A02:2021 — Cryptographic Failures

**The risk**: sensitive data exposed because of weak/missing crypto.

**Common forms**: HTTP instead of HTTPS, weak password hashing, hardcoded keys, deprecated TLS.

**Defenses**:
- HTTPS enforced (`deployment/nginx-reverse-proxy.md` redirects)
- HSTS header set
- bcrypt(cost=12+) or argon2id for passwords
- TLS 1.2+ only; modern cipher suites
- Encryption at rest on the DB (managed providers default this)
- Don't roll your own crypto — use library defaults

References: `deployment/lets-encrypt-ssl.md`, `backend/*/04-auth-*.md`

## A03:2021 — Injection

**The risk**: untrusted input interpreted as code (SQL, command, LDAP, etc.)

**Common forms**: SQL injection, NoSQL injection, OS command injection, ORM-bypass via raw SQL with concat, prompt injection in LLM apps.

**Defenses**:
- ORMs (SQLAlchemy, Drizzle, Prisma) parameterize by default
- Raw SQL: always parameterize via tagged template / `$1`-style
- Don't `os.system(user_input)` — use subprocess with arg list, no shell=True
- Validate inputs at API boundary (Pydantic, class-validator, zod)
- For LLMs: tag tool outputs as untrusted; don't auto-execute (`ai-agents/tool-use.md`)

References: `backend/*/02-*-and-migrations.md`, `ai-agents/tool-use.md`

## A04:2021 — Insecure Design

**The risk**: the system is fundamentally insecure even if implemented correctly.

**Common forms**: missing rate limiting, no MFA option, exposing internal IDs that enable enumeration, lack of separation between user/admin code paths.

**Defenses**:
- Threat model new features (`security/threat-modeling.md`)
- Rate limiting on auth endpoints, public API
- 2FA available for admin
- Defense in depth — don't rely on single layer

## A05:2021 — Security Misconfiguration

**The risk**: defaults left on, debug pages exposed, unnecessary features enabled.

**Common forms**: Swagger / Django admin / phpMyAdmin exposed in prod, default credentials, verbose error pages, missing security headers, unused services running.

**Defenses**:
- Lock down docs in prod (`/docs`, `/redoc` IP-restricted or disabled — see `deployment/per-framework/deploy-fastapi.md`)
- `server_tokens off` in nginx
- Generic error responses in prod (no stack traces)
- Security headers (HSTS, X-Frame-Options, CSP) per `deployment/nginx-reverse-proxy.md`
- UFW + fail2ban + automatic security updates per `deployment/ssh-and-remote-server-setup.md`

## A06:2021 — Vulnerable and Outdated Components

**The risk**: a dep with a known CVE.

**Defenses**:
- Lockfiles (`pnpm-lock.yaml`, `uv.lock`)
- Dependabot / Renovate auto-PRs
- `pnpm audit` / `pip-audit` in CI
- Pin Docker base images (`python:3.12-slim` not `python`)
- Image scanning (Trivy, Snyk) in CI

## A07:2021 — Identification and Authentication Failures

**The risk**: weak login, missing MFA, session bugs.

**Common forms**: no rate limit on login (allows brute force), session fixation, predictable session IDs, JWT without `exp`.

**Defenses**:
- Rate limit login (5/min/IP minimum)
- Session ID randomness via libs (don't roll your own)
- JWT with `exp` claim, short access token TTL, refresh tokens revocable
- Password length min 8, no max below 64
- Check breached-password lists (HaveIBeenPwned API) on signup
- 2FA available, required for admin

References: `backend/*/04-auth-*.md`

## A08:2021 — Software and Data Integrity Failures

**The risk**: untrusted code or data trusted as if it were trusted.

**Common forms**: deserializing untrusted data (Python pickle, Java ObjectInputStream), CDN supply chain (loading JS from compromised CDN), CI/CD pipeline tampered with.

**Defenses**:
- Don't deserialize untrusted data (no `pickle.loads(user_input)`)
- SRI for any external CSS/JS (`<script integrity="sha384-...">`)
- Sign deploy artifacts (cosign, see `cicd/github-actions-fastapi.md`)
- OIDC for cloud auth (`cicd/secrets-and-environments.md`)
- Required reviewer for prod deploys (GH Environments)

## A09:2021 — Security Logging and Monitoring Failures

**The risk**: you don't know when you've been compromised.

**Defenses**:
- Sentry / equivalent for app errors
- Log auth failures, privilege escalations, data access (audit log)
- Alerts on 5xx rate, auth failure spikes (Prometheus + Alertmanager — `observability/02-prometheus-grafana.md`)
- Centralized logs (Loki, CloudWatch) — searchable, retained 90+ days
- Audit trail for sensitive ops in DB or append-only log

## A10:2021 — Server-Side Request Forgery (SSRF)

**The risk**: server fetches a URL on behalf of a user, attacker passes a URL to an internal service or cloud metadata endpoint.

**Common forms**: image preview from URL, webhook delivery to user-supplied URL, OAuth callback URL, file import from URL.

**Defenses**:
- Allowlist URL hosts (only fetch from known domains)
- Block private IPs (`10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, `127.0.0.0/8`, link-local `169.254.0.0/16`)
- Block cloud metadata service (`169.254.169.254`)
- Use IMDSv2 (AWS) — requires session token, not stealable via SSRF
- Network egress firewall — block app servers from arbitrary outbound

```python
import ipaddress, socket

def is_safe_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ('http', 'https'): return False
    if parsed.hostname is None: return False
    try:
        ip = ipaddress.ip_address(socket.gethostbyname(parsed.hostname))
    except (socket.gaierror, ValueError):
        return False
    return not (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved)
```

(Note: this is best-effort — TOCTOU and DNS rebinding attacks defeat naive checks. For high-stakes apps, route through a hardened proxy like `gohttproxy` with allowlist.)

## Beyond OWASP 10

Things not on the list that matter:

- **Open redirect** (`?redirect=evil.com`) — allowlist
- **CSRF on state-changing endpoints** — SameSite=Lax + CSRF token
- **Mass assignment** — DTO with explicit allowlist of writable fields
- **Race conditions** on payments / signup — DB constraints + transactions
- **Subdomain takeover** — DNS pointing to abandoned cloud resources
- **Supply chain** — typosquatted packages (`reqeusts` vs `requests`)
- **Webhook signature verification** — verify Stripe / GitHub / etc. signatures

## When in doubt

- "Should this endpoint require auth?" — almost certainly yes; default deny.
- "Should I trust this user input?" — no; validate at boundary.
- "Should I log this?" — yes, but redact PII first.
- "Should I write custom crypto?" — no.
- "Should I expose this debug feature in prod?" — no.

References to specific defenses are scattered across:

- [`backend/*/04-auth-*.md`](../backend) — auth + middleware
- [`deployment/nginx-reverse-proxy.md`](../deployment/nginx-reverse-proxy.md) — TLS, headers
- [`security/security-review-checklist.md`](./security-review-checklist.md) — pre-launch
- [`security/threat-modeling.md`](./threat-modeling.md) — per-feature
- [`security/secrets-management.md`](./secrets-management.md) — secrets
