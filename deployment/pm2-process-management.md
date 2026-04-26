# PM2 Process Management

> Run Node.js apps reliably on a VPS — clusters, log rotation, graceful reload, startup hooks.

## Why PM2 (and the alternatives)

| Option | Verdict |
|--------|---------|
| **PM2** | Pick this for single-VPS Node deployments. Mature, ergonomic, includes log rotation, monit, startup hooks. |
| **systemd** | Built into Linux. Better for heterogeneous fleets. More verbose for Node. |
| **Docker Compose** | If you're already containerized, use compose's restart policy. Skip PM2. |
| **forever** | Old; PM2 superseded it. |
| **nodemon** | Dev only. Don't use in prod. |

For a Node app on a VPS without containers: **PM2**. With containers: **compose's `restart: unless-stopped`**.

## Install

```bash
# globally on the server
sudo npm install -g pm2
# or via pnpm
sudo pnpm add -g pm2
```

## Ecosystem config

`ecosystem.config.cjs` (CommonJS — PM2 doesn't load ESM configs reliably):

```javascript
module.exports = {
  apps: [
    {
      name: '{{project-slug}}-api',
      script: 'dist/server.js',
      cwd: '/var/www/{{project-slug}}',
      instances: 'max',                  // one per CPU
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
      },
      env_file: '.env',                  // PM2 loads dotenv-style file
      max_memory_restart: '512M',
      kill_timeout: 10000,               // 10s for graceful shutdown
      wait_ready: true,                  // app must call process.send('ready')
      listen_timeout: 10000,
      out_file: '/var/log/{{project-slug}}/out.log',
      error_file: '/var/log/{{project-slug}}/error.log',
      merge_logs: true,
      time: true,                        // prepend timestamp to logs
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    },
    {
      name: '{{project-slug}}-worker-emails',
      script: 'dist/queue/workers/email.worker.js',
      cwd: '/var/www/{{project-slug}}',
      instances: 2,
      exec_mode: 'fork',                 // workers don't cluster — parallelism via concurrency option
      env: { NODE_ENV: 'production' },
      env_file: '.env',
      max_memory_restart: '512M',
      kill_timeout: 30000,               // longer for in-flight job completion
      out_file: '/var/log/{{project-slug}}/worker-emails-out.log',
      error_file: '/var/log/{{project-slug}}/worker-emails-error.log',
      time: true,
    },
    {
      name: '{{project-slug}}-worker-billing',
      script: 'dist/queue/workers/billing.worker.js',
      cwd: '/var/www/{{project-slug}}',
      instances: 1,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      env_file: '.env',
      max_memory_restart: '512M',
      kill_timeout: 30000,
    },
  ],
};
```

### Why these specific settings

| Setting | Why |
|---------|-----|
| `cluster` mode | API uses Node's cluster module — utilizes all CPUs |
| `instances: 'max'` | One worker per CPU; tune lower if you want headroom |
| `exec_mode: 'fork'` for queue workers | Cluster mode is HTTP-oriented; for workers, fork mode + `instances: N` for parallelism |
| `wait_ready` + `process.send('ready')` | Coordinate with the load balancer / nginx — don't accept traffic until the app says it's ready |
| `kill_timeout: 10000` | Give graceful shutdown time before SIGKILL |
| `kill_timeout: 30000` for workers | Longer — let in-flight jobs finish |
| `max_memory_restart` | Auto-restart if leaked memory exceeds threshold |
| `time: true` | Prepends timestamp to log lines (PM2 doesn't by default) |

## App-side: graceful shutdown + ready signal

Your Node app should:

```typescript
import { createServer } from 'node:http';
import { createApp } from './app';

const app = createApp();
const server = createServer(app);

server.listen(env.PORT, () => {
  logger.info(`listening on ${env.PORT}`);
  if (process.send) process.send('ready');     // tells PM2 we're up
});

const shutdown = async (signal: string) => {
  logger.info({ signal }, 'shutting down');
  server.close(err => {
    if (err) { logger.error({ err }); process.exit(1); }
    process.exit(0);
  });
  // hard kill if graceful takes too long
  setTimeout(() => process.exit(1), 30_000).unref();
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

Without this, PM2 SIGKILLs after `kill_timeout` — losing in-flight requests.

## Operations

```bash
# start everything from the ecosystem
pm2 start ecosystem.config.cjs

# specific app
pm2 start ecosystem.config.cjs --only {{project-slug}}-api

# show status
pm2 list

# follow logs
pm2 logs                           # all apps
pm2 logs {{project-slug}}-api      # one app
pm2 logs --lines 200               # tail more

# graceful reload (zero downtime, cluster mode only)
pm2 reload {{project-slug}}-api
pm2 reload all

# hard restart (drops connections)
pm2 restart {{project-slug}}-api

# stop without removing from list
pm2 stop {{project-slug}}-api

# remove from process list
pm2 delete {{project-slug}}-api

# show details on a process
pm2 describe {{project-slug}}-api

# real-time monitor
pm2 monit
```

## Startup on boot

Make PM2 itself start at boot, plus auto-resurrect the saved process list:

```bash
# generate the startup script for your init system
pm2 startup systemd -u www-data --hp /home/www-data
# follow the printed instructions (one sudo command)

# save the current process list — this is what 'resurrect' brings back at boot
pm2 save
```

After a reboot, `pm2 list` shows everything as it was. **Re-run `pm2 save`** every time you change apps in the ecosystem.

## Log rotation

PM2 logs grow without bound by default. Install the rotation module:

```bash
pm2 install pm2-logrotate

# configure
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:rotateInterval '0 0 * * *'    # daily at midnight
```

Or use system `logrotate` — drop a config in `/etc/logrotate.d/{{project-slug}}`:

```
/var/log/{{project-slug}}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

Use `copytruncate` if PM2 keeps the file open without re-opening on rotation.

## Cluster mode + sticky sessions

Cluster mode round-robins HTTP across workers. **Each request can land on any worker.** This breaks:

- In-process state (don't have any)
- WebSocket connections (the WS expects to stay on the same worker)
- Server-Sent Events (same — long-lived)

For WebSocket apps, either:

- Run `instances: 1` (single worker) — fine for low-traffic
- Use a pub/sub layer (Redis, NATS) so workers share state
- Use `socket.io` with the Redis adapter

For SSE, similar — single instance or coordinate via Redis.

## Zero-downtime reload — how it works

`pm2 reload` (cluster mode):

1. Spawn new workers with the new code
2. Wait for `process.send('ready')` from each
3. Switch the load balancer to new workers
4. Send SIGINT to old workers
5. Old workers finish in-flight requests, then exit

This is why `wait_ready` matters. Without it, PM2 swaps to workers that aren't actually ready yet → 502s.

## Health check

Have an endpoint that confirms upstream deps:

```typescript
app.get('/health', async (_req, res) => {
  try {
    await db.execute(sql`SELECT 1`);
    await redis.ping();
    res.json({ status: 'ok', uptime: process.uptime() });
  } catch (err) {
    res.status(503).json({ status: 'degraded', error: (err as Error).message });
  }
});
```

PM2 itself doesn't poll your healthcheck. nginx, monitoring, and load balancers do. If you want PM2 to restart unhealthy processes, set `max_memory_restart` and write a small watchdog or use `pm2-health` plugin.

## Environment variables

PM2 reads from:

1. `env` block in ecosystem
2. `env_file: '.env'` (loads dotenv-style)
3. Process env at PM2 spawn time

`env_file` is the cleanest for production secrets. Don't commit `.env` — store on the server only, `chmod 600`.

For per-environment configs:

```javascript
env: { NODE_ENV: 'production' },
env_staging: { NODE_ENV: 'staging' },
```

```bash
pm2 start ecosystem.config.cjs --env staging
```

## Memory + CPU profiling

```bash
pm2 monit                        # live dashboard
pm2 describe {{project-slug}}-api  # heap, CPU, restarts
```

For deeper profiling, attach `node --inspect` and use Chrome DevTools, or use `clinic` (Node Foundation tool).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| App doesn't restart on reboot | `pm2 startup` + `pm2 save` after every ecosystem change |
| Reload drops connections | App needs to handle SIGINT gracefully and `process.send('ready')` |
| Logs eating disk | Install `pm2-logrotate` or use system `logrotate` |
| Cluster mode with single-process libs (sqlite, in-memory cache) | Use fork mode, or share via Redis |
| Workers not picking up jobs | Verify env vars are set in the worker — `env_file` covers this |
| PM2 daemon won't start | Check `~/.pm2/logs/`, often a permission issue |
| Memory keeps growing | `max_memory_restart: '512M'` as a safety net while you fix the leak |
| Wrong user owns process | Run `pm2 startup systemd -u <user>` to set the right user |
| Need to roll back fast | `pm2 reload all --update-env` after `git checkout <previous>` and rebuild |
| Multi-stage with pnpm `--frozen-lockfile` slow | Layer caching: copy lockfile first, install, then copy source |
