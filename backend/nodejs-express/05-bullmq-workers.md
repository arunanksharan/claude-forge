# BullMQ Workers (Express variant)

> Queue + worker setup without `@nestjs/bullmq`. Same library, plain wiring.

The full BullMQ patterns (concurrency, repeatable jobs, flows, monitoring) are in `backend/nestjs/05-bullmq-queues.md`. This file covers the **plain Node** wiring.

## Install

```bash
pnpm add bullmq ioredis
```

## Connection

`src/queue/connection.ts`:

```typescript
import IORedis from 'ioredis';
import { env } from '../config/env';

export const connection = new IORedis(env.REDIS_URL, {
  maxRetriesPerRequest: null,        // required by BullMQ
  enableReadyCheck: false,
});
```

**Reuse this connection** across queues and workers — don't create new ones per queue. Each connection is a TCP socket.

## Queue (producer side, in the API process)

`src/queue/queues.ts`:

```typescript
import { Queue } from 'bullmq';
import { connection } from './connection';

export const emailsQueue = new Queue('emails', {
  connection,
  defaultJobOptions: {
    removeOnComplete: { age: 24 * 3600, count: 1000 },
    removeOnFail: { age: 7 * 24 * 3600 },
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
  },
});

export const billingQueue = new Queue('billing', { connection, defaultJobOptions: { attempts: 5 } });
```

Add jobs from anywhere:

```typescript
import { emailsQueue } from '../queue/queues';

await emailsQueue.add('welcome', { userId }, { jobId: `welcome:${userId}` });
```

## Worker (separate process)

Workers run in their own Node process — not in the API. Reasons:

- Worker crashes don't take down the API
- You can scale workers independently
- Long jobs don't compete with HTTP for event loop time

`src/queue/workers/email.worker.ts`:

```typescript
import { Worker, type Job } from 'bullmq';
import { connection } from '../connection';
import { logger } from '../../lib/logger';
import { mailer } from '../../integrations/mailer';
import { db } from '../../db/client';
import { eq } from 'drizzle-orm';
import { users } from '../../db/schema';

interface WelcomeJob { userId: string }

const worker = new Worker(
  'emails',
  async (job: Job) => {
    switch (job.name) {
      case 'welcome': {
        const data = job.data as WelcomeJob;
        const user = await db.query.users.findFirst({ where: eq(users.id, data.userId) });
        if (!user) { logger.warn({ userId: data.userId }, 'welcome: user not found'); return; }
        await mailer.sendWelcome(user.email);
        return;
      }
      default:
        throw new Error(`unknown job: ${job.name}`);
    }
  },
  { connection, concurrency: 10 },
);

worker.on('failed', (job, err) => logger.error({ err, jobId: job?.id, name: job?.name }, 'job failed'));
worker.on('completed', (job) => logger.debug({ jobId: job.id, name: job.name }, 'job completed'));

const shutdown = async () => {
  logger.info('worker shutting down');
  await worker.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

Run it:

```bash
tsx src/queue/workers/email.worker.ts
# or in prod after build
node dist/queue/workers/email.worker.js
```

## PM2 ecosystem (running multiple workers)

`ecosystem.config.cjs`:

```javascript
module.exports = {
  apps: [
    {
      name: '{{project-slug}}-api',
      script: 'dist/server.js',
      instances: 'max',
      exec_mode: 'cluster',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '512M',
    },
    {
      name: '{{project-slug}}-worker-emails',
      script: 'dist/queue/workers/email.worker.js',
      instances: 2,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '512M',
    },
    {
      name: '{{project-slug}}-worker-billing',
      script: 'dist/queue/workers/billing.worker.js',
      instances: 1,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '512M',
    },
  ],
};
```

```bash
pm2 start ecosystem.config.cjs
pm2 logs
pm2 reload all
```

The API uses cluster mode (one instance per CPU). Workers use fork mode — BullMQ handles concurrency *within* a worker process via `concurrency:` option, plus you scale instances for resilience.

## Repeatable jobs at startup

```typescript
// src/queue/repeatable.ts (called from server.ts at boot)
import { emailsQueue } from './queues';

export async function registerRepeatable() {
  // dedupe by jobId so re-running this is safe
  await emailsQueue.add('daily-digest', { date: 'today' }, {
    repeat: { pattern: '0 9 * * *', tz: 'America/New_York' },
    jobId: 'daily-digest',
  });
}
```

```typescript
// server.ts
await registerRepeatable();
```

Repeatable jobs persist in Redis. Adding the same one with the same `jobId` is a no-op (won't create duplicates).

## Bull Board (web UI)

```bash
pnpm add @bull-board/api @bull-board/express
```

```typescript
// src/queue/admin.ts
import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter } from '@bull-board/express';
import { emailsQueue, billingQueue } from './queues';

export function mountBullBoard(app: import('express').Express) {
  const serverAdapter = new ExpressAdapter();
  serverAdapter.setBasePath('/admin/queues');
  createBullBoard({
    queues: [new BullMQAdapter(emailsQueue), new BullMQAdapter(billingQueue)],
    serverAdapter,
  });
  // protect with auth in real apps:
  app.use('/admin/queues', requireAdmin, serverAdapter.getRouter());
}
```

## Common pitfalls

Same as the Nest BullMQ guide. Plus, for plain Node:

| Pitfall | Fix |
|---------|-----|
| Worker process exits silently | Add `process.on('uncaughtException', ...)` and log; PM2 will restart |
| `connection` shared across queue + worker | Fine, but a single connection serializes ops — use separate connections per worker process |
| TypeScript build skips worker file | Ensure `tsup` / `tsc` includes `src/queue/workers/**` |
| Worker doesn't see schema imports correctly | Don't share top-level `db` across processes — each process initializes its own |
| Workers don't restart on deploy | Use PM2's `--update-env` or `pm2 reload all` (zero-downtime per cluster instance) |
| Queue names typo'd | `Queue('emails')` and `Worker('emails')` must match exactly. Centralize in `queue-names.ts` const. |
