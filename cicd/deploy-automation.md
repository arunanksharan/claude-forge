# Deploy Automation Patterns

> SSH-based deploys, blue-green strategies, rollback patterns, post-deploy verification.

## The deploy script — one source of truth

Whether triggered by GitHub Actions, a Slack `/deploy` command, or `make deploy`, route everything through the same script:

```bash
# /var/www/{{project-slug}}/scripts/deploy.sh
#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://localhost:8000/health}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-60}"
DEPLOY_DIR="$(dirname "$0")/.."

cd "$DEPLOY_DIR"

echo "===> deploying $IMAGE_TAG"

# 1. pull
echo "---> pulling image"
docker compose -f docker-compose.prod.yml pull api worker

# 2. backup current state (just record the running image)
PREV_IMAGE=$(docker inspect {{project-slug}}-api --format='{{.Config.Image}}' 2>/dev/null || echo "none")
echo "---> previous image: $PREV_IMAGE"

# 3. migrate
echo "---> running migrations"
docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head

# 4. rolling restart
echo "---> rolling restart"
docker compose -f docker-compose.prod.yml up -d --no-deps --remove-orphans api worker

# 5. wait for health
echo "---> health check"
START=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if [ $ELAPSED -gt $HEALTHCHECK_TIMEOUT ]; then
    echo "===> healthcheck timed out after ${HEALTHCHECK_TIMEOUT}s"
    echo "===> rolling back to $PREV_IMAGE"
    IMAGE_TAG="${PREV_IMAGE##*:}" docker compose -f docker-compose.prod.yml up -d --no-deps api worker
    exit 1
  fi
  if curl -fsS --max-time 3 "$HEALTHCHECK_URL" > /dev/null; then
    echo "===> healthy after ${ELAPSED}s"
    break
  fi
  sleep 2
done

# 6. cleanup old images (keep last 3 versions)
echo "---> pruning old images"
docker image prune -af --filter "until=720h" || true

echo "===> deployed $IMAGE_TAG successfully"
```

```bash
chmod +x scripts/deploy.sh
```

CI calls this:

```yaml
- run: ssh deploy@$HOST "/var/www/{{project-slug}}/scripts/deploy.sh main-${GITHUB_SHA::7}"
```

## Rollback strategy

### Easy rollback (image-based)

```bash
# manually
ssh deploy@$HOST "/var/www/{{project-slug}}/scripts/deploy.sh main-abc1234"
```

You're just deploying the previous image tag. **Always pin tags** (never `:latest`) so this is possible.

Track recent deploys somewhere (a `deploys.log`, a Slack channel, a release notes file) so you know what to roll back to.

### Hard cases

- **Migration is irreversible** (column dropped) → can't roll back database; have to roll forward. **This is why every PR with a migration should be reviewed extra carefully.** Use the **expand → migrate → contract** pattern (see `backend/fastapi/02-sqlalchemy-and-alembic.md`) so old code keeps working with new schema.
- **Stateful change** (data corrupted) → need backup restore. **Test backups quarterly** so you trust them.
- **External integration broke** → fix forward; rolling back the app doesn't help.

## Blue-green deploys (zero-downtime)

For zero-downtime without compose's brief swap:

```nginx
upstream api {
    server api-blue:8000  max_fails=2 fail_timeout=10s;
    server api-green:8000 max_fails=2 fail_timeout=10s;
}

location / { proxy_pass http://api; }
```

Run two replicas, swap one at a time:

```bash
# stop the one being upgraded
docker compose stop api-blue

# pull + start with new image
IMAGE_TAG=new docker compose up -d api-blue

# wait for it to be healthy
until docker exec api-blue wget -qO- http://localhost:8000/health > /dev/null 2>&1; do sleep 2; done

# repeat for green
docker compose stop api-green
IMAGE_TAG=new docker compose up -d api-green
```

For Next.js / Node where each instance is stateless, this works seamlessly.

For stateful services (websockets), you need session affinity or pub/sub coordination — see the per-framework deploy guides.

## Migration safety

```yaml
# always migrate BEFORE swapping the app
- run: |
    ssh deploy@$HOST bash -s <<'ENDSSH'
      cd /var/www/{{project-slug}}
      docker compose -f docker-compose.prod.yml run --rm api alembic upgrade head
      docker compose -f docker-compose.prod.yml up -d --no-deps api
    ENDSSH
```

If migration fails, app isn't redeployed → safe.

If migration succeeds but app deploy fails → you have new schema running with old app. Old app must tolerate the new schema. **This is why expand-only migrations are safe** (add columns, never drop in same release).

## Post-deploy verification

After SSH deploy succeeds:

```yaml
- name: Smoke test
  run: |
    sleep 5
    curl -fsSL https://api.example.com/api/v1/health
    curl -fsSL https://api.example.com/api/v1/version | jq -e '.version == "main-${GITHUB_SHA::7}"'

- name: Trigger Lighthouse run
  run: |
    npx @lhci/cli autorun --collect.url=https://example.com

- name: Wait for Sentry release adoption
  run: |
    sleep 60
    # query Sentry API: is the release receiving events?
```

## Notifications

Slack on success and failure (different channels):

```yaml
- name: Notify success
  if: success()
  uses: slackapi/slack-github-action@v1.27.0
  with:
    payload: |
      {"text":"✅ deployed {{project-slug}} v$IMAGE_TAG to ${{ inputs.target }} by ${{ github.actor }}"}
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_DEPLOYS_WEBHOOK }}

- name: Notify failure
  if: failure()
  uses: slackapi/slack-github-action@v1.27.0
  with:
    payload: |
      {"text":"❌ DEPLOY FAILED: {{project-slug}} ${{ inputs.target }}\n${{ github.run_url }}"}
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_ALERTS_WEBHOOK }}
```

Failure → loud channel (paged on-call). Success → quiet log channel.

## Auto-rollback on metric regression

Advanced: integrate with your observability so a deploy auto-rolls-back if error rate spikes:

```bash
# after deploy
sleep 120                       # let metrics accumulate
ERROR_RATE=$(curl -s "https://prom.example.com/api/v1/query?query=..." | jq '...')
if (( $(echo "$ERROR_RATE > 0.01" | bc -l) )); then
  echo "error rate $ERROR_RATE > 1% — rolling back"
  ./scripts/deploy.sh "$PREV_IMAGE_TAG"
  exit 1
fi
```

Most teams don't need this — manual roll-back from Slack alerts is fine. Add it when you find yourself doing it often.

## Deploy frequency philosophy

- **Many small deploys** beat few big ones — easier to identify what broke
- **Continuous to staging on every main merge** — staging should always reflect main
- **Production: gated** — require manual approval, ideally during low-traffic windows
- **Canary** for high-stakes changes — 5% of traffic for 1h before full rollout (requires nginx upstream weights or service mesh)

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Different env vars between staging and prod cause "works on staging" bugs | Use the same env var names; only values differ |
| Migration runs from two CI jobs simultaneously | Single-instance migration step; or app-level lock (`SELECT pg_try_advisory_lock(...)`) |
| Healthcheck succeeds but app is broken | Healthcheck must hit deps (DB, Redis), not just `/`. See `/health` patterns in deploy guides. |
| Slack noise (every deploy notifies) | Channel for deploys (info), separate for failures (paged) |
| No deploy log → "wait, what's running in prod?" | Deploy script writes to `/var/log/{{project-slug}}/deploys.log` with timestamp + tag + actor |
| Deploy from a fork's PR | Don't allow secrets exposure to forks; use `pull_request_target` carefully or restrict to org members |
| Stale Docker images filling disk | `docker image prune -af` on a schedule (weekly) |
| Force-deploy to skip CI | Don't allow it; if you must, document the reason in commit |
