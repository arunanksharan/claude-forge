# Secrets Management

> Where secrets live, how they get to apps, how to rotate, how to detect leaks.

> See also: [`cicd/secrets-and-environments.md`](../cicd/secrets-and-environments.md) for CI-side patterns.

## What's a secret

| Type | Examples |
|------|----------|
| **Auth** | passwords (hashed!), API keys, OAuth client secrets, JWT signing keys |
| **Connection strings** | DATABASE_URL, REDIS_URL with embedded creds |
| **Third-party** | Stripe keys, OpenAI keys, AWS access keys, Sentry DSN, Twilio tokens |
| **Internal** | SSH private keys, deploy keys, internal API tokens |
| **Symmetric crypto** | encryption keys (FERNET, AES) |
| **Personal** | Slack webhook URLs, personal API tokens |

Anything that gives access to a system or data is a secret. **Treat them all the same way.**

## Storage hierarchy

In ascending order of operational maturity:

| Storage | When it's enough |
|---------|------------------|
| `.env` file on each server (`chmod 600`) | Solo dev, 1-3 servers, small set of secrets |
| GitHub Secrets / GitLab CI Variables | Same scale + you have CI |
| Doppler / Infisical | 5+ services, want centralized rotation/audit |
| AWS Secrets Manager / GCP Secret Manager | If on AWS/GCP, multi-service, programmatic rotation |
| HashiCorp Vault | Enterprise, regulated, dynamic secrets |
| 1Password Secrets Automation | Team already on 1Password, prefer their UX |

**Don't over-engineer.** A `.env` file + `chmod 600` covers a real production for years. Migrate when you have a concrete need (rotation pain, audit requirement, multi-service growth).

**Don't under-engineer.** Past 5 services, point-to-point env files become unmanageable.

## The cardinal rules

1. **Never commit secrets to git** — even private repos. Even briefly.
2. **Different secret per environment** — staging compromised ≠ prod compromised.
3. **Different secret per service** when feasible — a leaked secret has a small blast radius.
4. **Rotate on personnel change** — anyone who's left should not be able to use any credential they had.
5. **Audit access** — who can see which secrets, who fetched what.
6. **Encrypt at rest** — managed secret stores do this; verify if rolling your own.
7. **Audit logs for secret access** — should exist + be reviewed.

## Naming conventions

```
{ENV}_{SERVICE}_{TYPE}_{PURPOSE}

PROD_API_DB_PASSWORD
STAGING_WORKER_REDIS_URL
PROD_WEB_STRIPE_PUBLISHABLE_KEY
PROD_WEB_STRIPE_SECRET_KEY
```

In code, just the type+purpose:

```
DATABASE_URL
REDIS_URL
STRIPE_SECRET_KEY
```

The env-prefix is for the secret store / CI scope. The app sees env-agnostic names.

## On-server `.env` setup

```bash
# one-time, on the server
sudo mkdir -p /var/www/{{project-slug}}
sudo chown deploy:deploy /var/www/{{project-slug}}

# create the env file
cat > /var/www/{{project-slug}}/.env <<'EOF'
DATABASE_URL=postgresql+asyncpg://app:CHANGEME@localhost/app
REDIS_URL=redis://localhost:6379/0
JWT_SECRET=CHANGEME-min-32-chars-long-secret
STRIPE_SECRET_KEY=sk_live_...
SENTRY_DSN=https://...@sentry.io/...
EOF

# critical
chmod 600 /var/www/{{project-slug}}/.env
chown deploy:deploy /var/www/{{project-slug}}/.env
```

Verify only `deploy` can read it:

```bash
ls -la /var/www/{{project-slug}}/.env
# -rw------- 1 deploy deploy 412 ... .env
```

## Docker patterns

### Reading from host env

```yaml
services:
  api:
    environment:
      - DATABASE_URL          # read from host shell at compose up
      - JWT_SECRET
```

Source from `.env` in the same dir (compose auto-loads):

```bash
docker compose --env-file /var/www/{{project-slug}}/.env up -d
```

### Docker secrets (Swarm mode)

If you use Docker Swarm:

```yaml
services:
  api:
    secrets:
      - db_password
secrets:
  db_password:
    external: true
```

Mounted at `/run/secrets/db_password` inside the container.

For Kubernetes: same idea via `Secret` resources.

## Programmatic fetching (Doppler / AWS Secrets Manager)

Pattern: fetch at startup, populate env, then run normally.

```bash
# wrapper script that runs your app
#!/usr/bin/env bash
set -euo pipefail
eval "$(doppler secrets download --no-file --format env)"
exec "$@"
```

```bash
./run-with-doppler.sh node dist/server.js
```

Or inside the app:

```python
import boto3, json

client = boto3.client('secretsmanager', region_name='us-east-1')
secret = json.loads(client.get_secret_value(SecretId='prod/api/secrets')['SecretString'])
os.environ.update(secret)
```

Trade-off: extra dependency, network call at startup, but centralized rotation.

## Rotation

For each secret, define rotation cadence:

| Secret | Cadence | Trigger |
|--------|---------|---------|
| JWT signing key | Annual | Or on suspected leak |
| DB password | Quarterly + on personnel change | |
| API keys (Stripe, OpenAI) | On personnel change | |
| SSH deploy keys | On personnel change | |
| Cloud creds (AWS access keys) | NEVER (use OIDC) | |
| OAuth client secrets | Per provider's recommendation | |

### JWT key rotation pattern (zero-downtime)

```python
# accept old + new during grace period
def verify(token: str) -> dict:
    for key in [JWT_SECRET_NEW, JWT_SECRET_OLD]:
        try:
            return jwt.decode(token, key, algorithms=['HS256'])
        except jwt.InvalidSignatureError:
            continue
    raise InvalidToken()

# sign with new
def sign(payload: dict) -> str:
    return jwt.encode(payload, JWT_SECRET_NEW, algorithm='HS256')
```

After all access tokens minted with old have expired (e.g. 24h after rotation), remove `JWT_SECRET_OLD`.

### DB password rotation

```sql
-- create new role
CREATE ROLE app_v2 WITH LOGIN PASSWORD 'NEW_PASSWORD';
GRANT app_role TO app_v2;

-- deploy app with new creds (uses app_v2)
-- verify all instances connected

-- drop old role
DROP ROLE app;
```

## Detection — find leaks

### Pre-commit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.0
    hooks:
      - id: gitleaks
```

`gitleaks` scans for known secret patterns (Stripe keys, AWS keys, JWT, etc.). Catches accidents before commit.

### CI

```yaml
- uses: trufflesecurity/trufflehog@main
  with:
    base: ${{ github.event.pull_request.base.sha }}
    head: ${{ github.event.pull_request.head.sha }}
```

Catches secrets in PR diffs.

### Repo-wide history scan

```bash
# scan entire git history (slow)
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest detect --source=/repo --report-path=/repo/leaks.json
```

For new repos: clean. For old repos: expect findings; rotate any secret found.

### GitHub's built-in

GitHub Settings → Secret scanning. Auto-detects 200+ secret types in commits. Free for public repos; paid for private. **Enable it.**

## What to do if a secret leaks

1. **Rotate the secret immediately**. Don't wait to "investigate first."
2. **Identify scope**: where does it grant access? Who could have stolen it?
3. **Audit usage**: check provider logs (Stripe, AWS, etc.) for unauthorized use.
4. **Remove from history if applicable**:
   ```bash
   # use BFG Repo-Cleaner
   bfg --delete-files .env
   git push --force
   ```
   But assume it's leaked anyway — anyone who cloned has a copy.
5. **Postmortem**: how did it happen? What process change prevents recurrence?
6. **Notify** affected parties if user data was at risk.

## Anti-patterns

| | |
|---|---|
| `.env` committed "just for now" | Will leak; always |
| Same JWT secret across staging + prod | Staging compromise = prod compromise |
| Secrets in URLs (?api_key=...) | Logged everywhere; never in URLs |
| Secrets in client-side JS | Anything in client is public |
| Password "encryption" with reversible cipher | Hash, never encrypt |
| "We'll rotate later" | You won't; do it now or schedule it |
| Sharing secrets via Slack DM | Use a real password manager / secret store |
| One AWS user with admin everywhere | Per-service IAM roles, least privilege |
| Devs have prod credentials | Use a bastion or jit-access via SSO |

## Auditing

Quarterly:

- [ ] List all production secrets — when last rotated?
- [ ] List who has access to each secret store — anyone left the team since last review?
- [ ] Review CI / cloud audit logs — any unusual secret access?
- [ ] Scan repos with gitleaks / GitHub secret scanning — any new leaks?
- [ ] Verify backup encryption keys are recoverable (test restore!)

Annual:

- [ ] Re-evaluate secret store choice (have you outgrown `.env`? Doppler? Vault?)
- [ ] Rotate any secret that hasn't been rotated in 12 months
- [ ] Review IAM principle-of-least-privilege

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `.env.example` has real-looking values | Use `CHANGEME` or `<your-key-here>` placeholders |
| `.env` lost during deploy | Backup secret store separately; `.env` should be reproducible |
| App reads `os.environ['X']` and crashes if missing | Use a settings library that fails fast at startup with clear error |
| Secret stored in container image layer | Use multi-stage build; never `COPY .env` into final image |
| Same secret in multiple services | Centralized store + fetched at startup |
| Secret in CI logs | `add-mask::` or never `echo`; check workflow runs |
| Backup contains secrets | Encrypt backups; restrict access |
| OAuth client secret committed | Most providers can revoke + reissue; do it now |
