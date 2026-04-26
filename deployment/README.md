# Deployment — claudeforge guides

> *Phase 2 — coming soon.* End-to-end VPS deployment patterns: docker-compose orchestration, nginx reverse proxy, PM2 for Node processes, SSH bootstrap from a fresh server, Let's Encrypt SSL via certbot.

## Files

### Cross-cutting

- `docker-compose-patterns.md` — *Phase 2* — multi-service compose layouts, healthchecks, named volumes, env management, prod vs dev compose files
- `nginx-reverse-proxy.md` — *Phase 2* — server blocks, SSE/WebSocket support, rate limiting, security headers, gzip/brotli
- `pm2-process-management.md` — *Phase 2* — ecosystem.config.js, cluster mode, log rotation, startup hooks
- `ssh-and-remote-server-setup.md` — *Phase 2* — fresh-server bootstrap (Ubuntu 22.04/24.04): users, sudo, ssh key auth, ufw firewall, fail2ban, swap, automatic security updates
- `lets-encrypt-ssl.md` — *Phase 2* — certbot via the nginx plugin, DNS challenge for wildcards, auto-renewal, staging vs prod

### Per-framework

- `per-framework/deploy-nextjs.md` — Next.js 15 standalone build behind nginx
- `per-framework/deploy-fastapi.md` — uvicorn (single + multi-worker) behind nginx
- `per-framework/deploy-nestjs.md` — Nest behind PM2 cluster mode behind nginx
- `per-framework/deploy-nodejs.md` — Plain Node/Express behind PM2 + nginx
