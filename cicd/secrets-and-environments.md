# Secrets & Environments in CI/CD

> GitHub Secrets vs Environments vs OIDC. Where each value lives. How to keep secrets out of logs and out of forks.

## Three levels in GitHub Actions

| Level | Where | Use for |
|-------|-------|---------|
| **Repository secrets** | Settings → Secrets → Actions → Repository | Default — values shared across all envs |
| **Environment secrets** | Settings → Environments → `{env}` → Secrets | Per-env values (different prod vs staging) |
| **Repository variables** | Settings → Secrets → Variables | Non-secret config (region, service name) |
| **Organization secrets** | Org Settings → Secrets | Shared across many repos (e.g. shared Sentry token) |

Use the most specific level. **Don't put production secrets in Repository secrets** — they leak to every workflow run, including PRs from contributors.

## Environments — the gating mechanism

Environments are not just secret stores. They give you:

- **Required reviewers** — production deploys need a human approval
- **Wait timer** — delay deploys for X minutes
- **Deployment branch restrictions** — `production` only deployable from `main` or tags
- **Audit log** — who deployed what, when

Set up `staging` (auto-deploy) and `production` (gated):

```
Settings → Environments → New environment

production:
  Required reviewers: [you, lead-dev]
  Wait timer: 0 minutes
  Deployment branches: Only protected branches + tags

staging:
  Required reviewers: (none)
  Deployment branches: main only
```

Reference in workflow:

```yaml
jobs:
  deploy:
    environment: production         # uses production's secrets + gate
```

## OIDC for cloud (no long-lived keys)

For AWS/GCP/Azure, **never store long-lived keys in GitHub Secrets**. Use OIDC:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-deploy
      aws-region: us-east-1

  - run: aws s3 sync ./build s3://my-bucket/
```

In AWS, set up an IAM Identity Provider for `token.actions.githubusercontent.com`, then a role with a trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main" }
    }
  }]
}
```

The `sub` condition restricts the role to specific repo + branch. Lock it tight.

GCP / Azure / Cloudflare have analogous OIDC setups. Same idea: short-lived tokens, no rotation.

## Secrets across environments

Pattern: same name, different values:

| Secret | Repository default | Staging | Production |
|--------|-------------------|---------|-----------|
| `DATABASE_URL` | (none) | postgresql://...staging-db... | postgresql://...prod-db... |
| `JWT_SECRET` | (none) | staging-secret-32 | prod-secret-different-32 |
| `SENTRY_DSN` | (none) | https://...@sentry.io/staging | https://...@sentry.io/prod |
| `STRIPE_SECRET_KEY` | (none) | sk_test_... | sk_live_... |

In the workflow:

```yaml
jobs:
  deploy:
    environment: ${{ inputs.target }}    # 'staging' or 'production'
    steps:
      - run: |
          ssh deploy@$HOST "DATABASE_URL=${{ secrets.DATABASE_URL }} ./deploy.sh"
```

GitHub auto-loads the matching environment's secrets. Same workflow, different secrets.

## Secrets in `.env` on the server

CI doesn't need to push `.env` every deploy — it's stored on the server:

```bash
# on server, one-time setup
cat > /var/www/{{project-slug}}/.env <<EOF
DATABASE_URL=postgresql://...
JWT_SECRET=...
EOF
chmod 600 /var/www/{{project-slug}}/.env
chown deploy:deploy /var/www/{{project-slug}}/.env
```

Docker compose reads via `env_file: .env` or `environment:` (passing through host env).

For rotation: SSH + edit + restart. Or use a real secret manager (Vault, AWS Secrets Manager, Doppler).

## Doppler / Infisical / Vault

For >10 services or >50 secrets, use a centralized secret manager:

| Tool | When |
|------|------|
| **Doppler** | Easy SaaS, great DX |
| **Infisical** | OSS Doppler-alike |
| **AWS Secrets Manager** | If on AWS |
| **HashiCorp Vault** | Enterprise / self-hosted |
| **1Password Secrets Automation** | If your team uses 1Password |

Pull secrets at deploy time via SDK or CLI. Avoids GitHub becoming the source of truth for secrets.

## Keeping secrets out of logs

GitHub Actions auto-masks values matching registered secrets. Defenses:

1. **Use `secrets.X` syntax** — auto-masked
2. **Don't `echo "$SECRET"`** — even masked, the redaction is best-effort
3. **`add-mask::***` for derived values**:
   ```bash
   COMPUTED=$(some-command)
   echo "::add-mask::$COMPUTED"
   ```
4. **Don't `set -x`** in bash sections handling secrets
5. **Avoid putting secrets in URL paths** (curl logs URLs); use headers

## Secrets and forks

PRs from forks can't see your repo secrets — by design. But:

- `pull_request_target` event runs in the **base repo's context with secrets** — dangerous if it checks out untrusted code
- **Never use `pull_request_target` to checkout fork code and run it** unless you've manually reviewed

For first-time contributors, GitHub auto-requires approval before workflows run on their PRs. Keep this enabled.

## Rotating secrets

Plan for it:

| Secret | Rotation cadence |
|--------|------------------|
| JWT signing key | Annually (with grace period for old keys) |
| Database password | When personnel changes; quarterly otherwise |
| API keys (Stripe, OpenAI, etc.) | When personnel changes; on suspected exposure |
| SSH deploy key | When personnel changes |
| Cloud credentials | OIDC eliminates this need |

For JWT key rotation:
1. Add `JWT_SECRET_NEW`
2. Update verification to accept both old and new
3. Update signing to use new
4. Wait long enough that all access tokens minted with old have expired (e.g. 24h)
5. Remove old secret + verification

## Pre-flight: how to tell if secrets are leaking

- **GitHub's secret scanning** auto-detects committed secrets in some formats — enable it
- **TruffleHog / GitGuardian** in CI — scans every PR
- **Sentry's PII filter** — scrub request bodies
- **`docker logs` audit** — make sure your app doesn't log creds

```yaml
# .github/workflows/secret-scan.yml
- uses: trufflesecurity/trufflehog@main
  with:
    base: ${{ github.event.pull_request.base.sha }}
    head: ${{ github.event.pull_request.head.sha }}
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Secret committed to git history | Rotate it immediately. Use `git filter-branch` / BFG to remove from history. Assume it's leaked even if you remove. |
| Production secret in PR-triggered workflow | Use Environments — production secrets only available in production environment jobs |
| `echo $SECRET` in CI logs | Don't. Use `add-mask` or just don't print |
| Same JWT secret across envs | Each env unique. If staging is compromised, prod isn't. |
| Forgot to add `id-token: write` for OIDC | Auth fails — set in `permissions:` |
| Long-lived AWS_ACCESS_KEY_ID still in secrets | Migrate to OIDC; delete the old keys after grace period |
| `.env.example` accidentally has real values | Always `.env.example` with placeholders; .env is gitignored |
| Deploy SSH key has too-broad access | Per-server, per-environment SSH keys; restrict via authorized_keys options |
| Slack webhook URL in plain commit | These are auth — treat as secrets |
