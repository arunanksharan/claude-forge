---
name: deploy-docker-nginx-ssl
description: Use when the user wants to deploy an app to a VPS with docker-compose + nginx reverse proxy + Let's Encrypt SSL. Covers compose patterns, nginx server blocks (HTTPS redirect, security headers, SSE/WebSocket, rate limit), certbot for SSL with auto-renewal. Triggers on "deploy to vps", "set up nginx", "lets encrypt", "deploy with docker compose", "add ssl".
---

# Deploy with Docker Compose + nginx + SSL (claudeforge)

Combine these guides:

- `deployment/docker-compose-patterns.md` — compose layouts, healthchecks, networks
- `deployment/nginx-reverse-proxy.md` — server blocks, SSE/WS, headers, rate limit
- `deployment/lets-encrypt-ssl.md` — certbot with HTTP-01 (or DNS-01 for wildcards)
- The framework-specific deploy guide (`deployment/per-framework/deploy-{nextjs|fastapi|nestjs|nodejs}.md`)

Steps:

1. **Confirm parameters with the user**:
   - Framework (Next.js, FastAPI, NestJS, Node/Express)
   - Domain (and whether they want www → apex redirect)
   - Are they using Docker, or systemd/PM2 directly?
   - Other services (Postgres, Redis, workers)?
2. **Verify prerequisites** with the user:
   - VPS already bootstrapped (point to `deploy-vps-bootstrap` if not)
   - Domain DNS pointing to the server (A and AAAA)
   - Port 80 reachable (for ACME challenge)
3. **Generate the deployment artifacts**:
   - `docker-compose.prod.yml` per the framework's deploy guide (compose pattern from `docker-compose-patterns.md`)
   - `nginx/conf.d/{{domain}}.conf` — first an HTTP-only version for getting the cert
   - `Dockerfile` (multi-stage, non-root user, healthcheck)
   - `Makefile` with `prod`, `migrate`, `logs`, `shell` targets
4. **Walk the user through deployment**:
   - Push code, ssh to server, clone, set `.env`
   - Bring up nginx + the app on HTTP first
   - Verify the app responds (`curl -I http://{{domain}}`)
   - Run certbot: `sudo certbot --nginx -d {{domain}} -d www.{{domain}}` for SSL
   - Verify HTTPS, A+ rating on ssllabs.com
   - Configure auto-renewal cron / hooks if needed
5. **Confirm post-deploy**:
   - `pm2 startup && pm2 save` (if PM2)
   - `systemctl enable {{service}}` (if systemd)
   - Backup script + monitoring set up (point to `observability/` skills)

Be deliberate about each step. Verify health after each change.
