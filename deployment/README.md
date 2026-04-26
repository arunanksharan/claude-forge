# Deployment — claudeforge guides

> *Phase 2 — coming soon.* End-to-end VPS deployment patterns: docker-compose orchestration, nginx reverse proxy, PM2 for Node processes, SSH bootstrap from a fresh server, Let's Encrypt SSL via certbot.

## Files

### Cross-cutting

- [`docker-compose-patterns.md`](./docker-compose-patterns.md) — multi-service compose layouts, healthchecks, named volumes, env management, prod vs dev compose files
- [`nginx-reverse-proxy.md`](./nginx-reverse-proxy.md) — server blocks, SSE/WebSocket support, rate limiting, security headers, gzip/brotli
- [`pm2-process-management.md`](./pm2-process-management.md) — ecosystem config, cluster mode, log rotation, startup hooks
- [`ssh-and-remote-server-setup.md`](./ssh-and-remote-server-setup.md) — fresh-server bootstrap (Ubuntu 22.04/24.04): users, sudo, ssh key auth, ufw firewall, fail2ban, swap, automatic security updates
- [`lets-encrypt-ssl.md`](./lets-encrypt-ssl.md) — certbot via the nginx plugin, DNS challenge for wildcards, auto-renewal, A+ rating

### Per-framework

- [`per-framework/deploy-nextjs.md`](./per-framework/deploy-nextjs.md) — Next.js 15 standalone build behind nginx
- [`per-framework/deploy-fastapi.md`](./per-framework/deploy-fastapi.md) — gunicorn + uvicorn workers behind nginx
- [`per-framework/deploy-nestjs.md`](./per-framework/deploy-nestjs.md) — Nest cluster + workers behind nginx
- [`per-framework/deploy-nodejs.md`](./per-framework/deploy-nodejs.md) — Plain Express behind PM2 + nginx
