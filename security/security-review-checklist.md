# Pre-Launch Security Review Checklist

> Run through this before going live. Tick each box. If you can't tick it, fix it or document why.

## Transport

- [ ] **HTTPS everywhere.** No HTTP except the ACME challenge endpoint.
- [ ] **HTTP → HTTPS redirect.** 301 from port 80 to 443 (everything else under /). Exception: `/.well-known/acme-challenge/`.
- [ ] **HSTS enabled** with `max-age=63072000; includeSubDomains`. (Add `preload` only after deliberation.)
- [ ] **TLS 1.2+ only.** TLS 1.0/1.1 disabled.
- [ ] **A or A+ rating** at https://www.ssllabs.com/ssltest/ for production hostnames.
- [ ] **Certificate auto-renewal** verified (`certbot renew --dry-run` succeeds).
- [ ] **Cipher suite** uses ECDHE forward secrecy.

## Headers

- [ ] `Strict-Transport-Security: max-age=63072000; includeSubDomains`
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `X-Frame-Options: DENY` or `SAMEORIGIN` (or use `Content-Security-Policy: frame-ancestors`)
- [ ] `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] `Permissions-Policy` set (camera/microphone/geolocation locked unless used)
- [ ] `Content-Security-Policy` defined (start with `Report-Only`, then enforce)
- [ ] `Server:` header doesn't leak version (nginx `server_tokens off`)

Test: https://securityheaders.com/?q=your-domain.com — aim for A+.

## Authentication

- [ ] **Password storage**: bcrypt (cost ≥12), argon2id, or scrypt. Not SHA-* or MD5.
- [ ] **Password requirements**: ≥8 chars, no max length below 64 (allow long passwords + passphrases).
- [ ] **Rate limit on login**: 5/min/IP minimum; lock after N failed attempts.
- [ ] **JWT signing key** at least 256 bits, unique per environment, in env (not committed).
- [ ] **JWT verify**: explicit `algorithms=['HS256']` (or whichever) — never default to None.
- [ ] **Access tokens short-lived** (≤30min); refresh tokens longer but revocable.
- [ ] **Refresh token storage**: httpOnly + Secure + SameSite=Lax/Strict cookie.
- [ ] **Session invalidation on logout**: deny-list refresh tokens or use short access TTL only.
- [ ] **Email verification flow** if accounts are public sign-up.
- [ ] **2FA available** for admin accounts (TOTP or WebAuthn).
- [ ] **Account lockout** after N failed logins (with reset path).

## Authorization

- [ ] **Default deny**: every endpoint requires auth unless explicitly `@Public`.
- [ ] **RBAC checks** at the service or guard layer (not only frontend).
- [ ] **Resource-level checks** (`actor owns this resource`) — not only role-based.
- [ ] **Multi-tenant filter**: every query filtered by tenant; ideally enforced via RLS or middleware.
- [ ] **No `is_admin` flag inferred from JWT alone** without DB lookup if role can change.
- [ ] **API keys hashed** (sha256) at rest; only first 8 chars indexed for lookup.

## Input handling

- [ ] **Validation at boundary**: every request body validated (Pydantic / class-validator / zod).
- [ ] **Parameterized queries** everywhere. No string concatenation into SQL or NoSQL.
- [ ] **ORM** rather than raw SQL when possible. If raw SQL: parameterized.
- [ ] **File upload limits**: type allowlist, size cap, virus scan if user-facing.
- [ ] **Filename sanitization** if storing user-supplied names.
- [ ] **Path traversal** defenses: never accept user-supplied file paths.
- [ ] **URL parsing** for user-supplied URLs (don't construct via concatenation).
- [ ] **HTML escaping** in templates (frameworks usually default this — verify).
- [ ] **XSS-safe React/Vue/Angular** — never `dangerouslySetInnerHTML` with user input without sanitization (DOMPurify).
- [ ] **JSON parsing limits** — set body size limits (1MB usually fine; larger only if needed).

## Data

- [ ] **Encryption at rest**: managed DB providers do this; verify if self-hosted.
- [ ] **PII inventory**: list every PII field; document why it's collected.
- [ ] **PII access logged** (audit trail) if regulated.
- [ ] **Backups encrypted** in transit and at rest; access-controlled.
- [ ] **GDPR / CCPA**: data export + delete endpoints implemented.
- [ ] **Sensitive data redacted from logs** (passwords, tokens, full credit card numbers).
- [ ] **Secrets not logged**: pino/structlog redact paths configured.
- [ ] **Database backups tested restore** (within last 90 days).

## Secrets

- [ ] **No secrets in git history**. Verified via `truffleHog` / GitGuardian / GH secret scanning.
- [ ] **`.env` in `.gitignore`**, `.env.example` has only placeholders.
- [ ] **Secrets in env vars or secret manager**, not in code.
- [ ] **Per-environment secrets**: prod and staging have different values.
- [ ] **Rotated secrets**: JWT signing key, DB passwords rotated within last year.
- [ ] **OIDC** instead of long-lived AWS/GCP keys in CI.
- [ ] **Production access** limited (named individuals, audit log).

## Dependencies

- [ ] **Lockfiles committed** (`pnpm-lock.yaml`, `uv.lock`, etc.).
- [ ] **`pnpm audit` / `uv pip audit`** clean of high/critical (or documented mitigations).
- [ ] **Dependabot / Renovate** enabled with auto-PR for security updates.
- [ ] **No deprecated/abandoned packages** in critical paths.
- [ ] **License audit** — no GPL in proprietary product (unless allowed).

## Infrastructure

- [ ] **SSH password auth disabled**, key-only.
- [ ] **Root SSH disabled**.
- [ ] **UFW / firewall** allows only necessary ports (22, 80, 443).
- [ ] **fail2ban** active for SSH.
- [ ] **Automatic security updates** enabled (`unattended-upgrades`).
- [ ] **Docker containers run as non-root** user.
- [ ] **Docker image scanning** (Trivy / Snyk) in CI.
- [ ] **No `:latest` in production deploys** — pin digest or version tag.
- [ ] **Network segmentation**: DB not exposed to public internet.
- [ ] **Bastion / VPN** for admin access to prod (no direct SSH from internet for admins).
- [ ] **Cloud IAM principle of least privilege** — no `*:*` policies.

## Application

- [ ] **CSRF protection** for cookie-auth flows. SameSite=Lax/Strict + CSRF token for state-changing endpoints.
- [ ] **CORS** allowlist (no wildcard `*` in production).
- [ ] **Rate limiting** on public endpoints — sign-in, sign-up, search, expensive endpoints.
- [ ] **Webhook signatures** verified (Stripe, GitHub, etc.).
- [ ] **Open redirect** check: any `?redirect=` param validated against allowlist.
- [ ] **Content-Disposition** for file downloads (force download, prevent serving as HTML).
- [ ] **Bot protection** if needed (Cloudflare Turnstile, hCaptcha) on sensitive endpoints.

## Observability + incident response

- [ ] **Errors go to Sentry** (or equivalent) — operators know when prod breaks.
- [ ] **Alerting on**: 5xx rate, p99 latency, auth failure spikes, unusual data access.
- [ ] **Audit log** for sensitive operations (admin actions, data exports, role changes).
- [ ] **Incident runbook** exists — who's on call, how to roll back, who to notify.
- [ ] **Backups + restore documented** — and someone has actually done a test restore.

## Web app specific

- [ ] **OAuth redirect URIs** allowlisted in provider settings, no wildcards.
- [ ] **Subresource Integrity (SRI)** for any externally hosted JS/CSS.
- [ ] **Cookies marked `Secure`, `HttpOnly`, `SameSite`** as appropriate.
- [ ] **Login form**: `autocomplete="current-password"`, no autocomplete leak.
- [ ] **Logout invalidates session server-side** (not just clears cookie).

## Mobile app specific

- [ ] **Certificate pinning** for high-stakes APIs (debatable for general apps).
- [ ] **Tokens in secure storage** (Keychain / Keystore / SecureStore) — not AsyncStorage / shared prefs.
- [ ] **Code obfuscation** if app contains business logic worth protecting (Flutter/RN: ProGuard / Hermes minify).
- [ ] **Jailbreak / root detection** for high-stakes apps (banking, etc.).
- [ ] **Deep link validation** — don't trust deep link params blindly.

## AI / LLM specific

- [ ] **Prompt injection defenses**: tool outputs marked as untrusted; system prompt firm.
- [ ] **PII not sent to third-party LLM providers** unless contracted (or use provider with HIPAA/SOC2).
- [ ] **Cost caps**: per-user, per-day budget.
- [ ] **Model output sanitization** if rendering: don't `dangerouslySetInnerHTML` LLM output.
- [ ] **Tool permissions** scoped to acting user — never the model's specified user_id.
- [ ] **Rate limit on AI endpoints** — they're expensive to abuse.

## Compliance gates (if applicable)

- [ ] **GDPR** — privacy policy, data subject rights, breach notification process
- [ ] **CCPA** — opt-out, "do not sell"
- [ ] **HIPAA** — BAA with cloud provider, encryption, audit log
- [ ] **PCI** — never store card numbers; use Stripe / equivalent tokenization
- [ ] **SOC 2** — formal program, controls audited

## Sign-off

- [ ] Security review by someone who didn't write the code
- [ ] Penetration test (external) for high-stakes products
- [ ] Bug bounty program for ongoing
- [ ] Privacy policy + terms reviewed by counsel for material products

## Cadence after launch

- **Weekly**: review Sentry / SIEM alerts, dependency PRs
- **Monthly**: review IAM, access logs
- **Quarterly**: rotate non-OIDC secrets, full dep audit, restore-from-backup test
- **Yearly**: full security review, pen test, threat model refresh
