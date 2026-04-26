# LiveKit — Self-hosted WebRTC

> Production config for self-hosted LiveKit server. Use for voice/video apps, AI voice agents (Pipecat), real-time collaboration.

## When to self-host LiveKit vs LiveKit Cloud

| Self-host | LiveKit Cloud |
|-----------|---------------|
| Compliance / data residency | Default — zero ops |
| Predictable cost at scale | Pay per minute, scales to zero |
| You already operate Redis + nginx | You don't want to manage TURN |
| Need custom server-side hooks | Standard webhook callbacks suffice |

## Files

- [`livekit.yaml`](./livekit.yaml) — production config (sanitized)
- [`README.md`](./README.md) — this file

## Required infrastructure

- **Redis** — for room state across instances. Use `shared-stack/redis` from the infra-recipes.
- **TURN over TLS** — for clients behind strict firewalls. Requires:
  - DNS A record for `turn.${DOMAIN}` pointing to your server
  - Let's Encrypt cert for `turn.${DOMAIN}` (certbot)
  - Open ports: UDP 3478, TCP 5349, UDP 50000-50100, TCP 7880, TCP 7881
- **Public IP** — set in `livekit.yaml` `rtc.node_ip`
- **API key + secret** — generate with `livekit-server generate-keys`

## Docker Compose snippet

```yaml
services:
  livekit:
    image: livekit/livekit-server:latest        # pin a version in prod
    container_name: app-livekit
    command: ["--config", "/etc/livekit.yaml"]
    restart: unless-stopped
    ports:
      - '${LIVEKIT_PORT:-7880}:7880'
      - '7881:7881'
      - '50000-50100:50000-50100/udp'
      - '3478:3478/udp'
      - '5349:5349'
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml:ro
      - /etc/letsencrypt/live/${TURN_DOMAIN}/fullchain.pem:/etc/livekit/turn.crt:ro
      - /etc/letsencrypt/live/${TURN_DOMAIN}/privkey.pem:/etc/livekit/turn.key:ro
    environment:
      LIVEKIT_KEYS: '${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}'
    networks:
      - app-network
    depends_on:
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits: { cpus: '2', memory: 2G }

networks:
  app-network:
    external: true
```

## nginx config

See [`../nginx-templates/livekit-turn.conf`](../nginx-templates/livekit-turn.conf).

## UFW

```bash
sudo ufw allow 7880/tcp                   # signaling (proxy via nginx in prod)
sudo ufw allow 7881/tcp                   # RTC TCP
sudo ufw allow 3478/udp                   # TURN UDP
sudo ufw allow 5349/tcp                   # TURN-TLS
sudo ufw allow 50000:50100/udp            # WebRTC media
```

## Generate keys

```bash
docker run --rm livekit/livekit-server:latest generate-keys
```

Output:

```
KEY1=secret1
```

Use as `LIVEKIT_API_KEY=KEY1` and `LIVEKIT_API_SECRET=secret1` in your env. **Note**: the format in `livekit.yaml` requires `KEY: SECRET` with a space after the colon.

## Verify

```bash
# server health
curl http://localhost:7880/

# generate a join token (uses your API key/secret)
docker exec app-livekit livekit-cli create-token \
    --api-key "$LIVEKIT_API_KEY" \
    --api-secret "$LIVEKIT_API_SECRET" \
    --identity "test-user" \
    --room "test-room" \
    --join

# inspect with livekit-cli
livekit-cli list-rooms --url http://localhost:7880 --api-key ... --api-secret ...
```

## For AI voice agents

LiveKit pairs with Pipecat for AI voice apps. The agent connects as a participant; user speaks; agent processes (STT → LLM → TTS) and streams audio back.

For the agent + memory architecture, see [`memory-layer/01-dual-memory-architecture.md`](../../memory-layer/01-dual-memory-architecture.md) — the voice prefetch flow that keeps p99 < 500ms.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Clients can't connect (corp firewall) | Enable TURN-TLS on 5349; verify DNS + cert |
| Audio cuts in / out | Check UDP port range firewall + node_ip set correctly |
| Recording not working | Need separate egress service (`livekit/egress`) |
| Multiple instances disagree about rooms | Configure Redis correctly; all instances same Redis |
| Cert expires without restart | LiveKit reads cert at start; reload after cert renewal |
| `LIVEKIT_KEYS` format error | Note the SPACE after the colon: `KEY: SECRET` not `KEY:SECRET` |
| High CPU | Each room ~50 MB / 0.1 CPU per participant; scale horizontally with Redis |
