# BullMQ (Node) — Production Setup

> The full reference is in `backend/nestjs/05-bullmq-queues.md` (Nest) and `backend/nodejs-express/05-bullmq-workers.md` (plain Node). This file consolidates the standalone patterns.

## Install

```bash
pnpm add bullmq ioredis
```

## Connection

```typescript
// src/queue/connection.ts
import IORedis from 'ioredis';
import { env } from '../config/env';

export const connection = new IORedis(env.REDIS_URL, {
  maxRetriesPerRequest: null,        // required by BullMQ
  enableReadyCheck: false,
});
```

Reuse this connection across queues and workers — don't create new ones per queue.

## Queue (producer side)

```typescript
// src/queue/queues.ts
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
export const longQueue    = new Queue('long', { connection });
```

### Why these defaults

- `removeOnComplete` / `removeOnFail` — prevent Redis from filling up
- `attempts: 3` + exponential backoff — handles transient failures
- Failed jobs retained 7d for debugging

## Adding jobs

```typescript
import { emailsQueue } from '../queue/queues';

await emailsQueue.add('welcome', { userId }, {
  jobId: `welcome:${userId}`,         // dedupe via stable id
  delay: 0,
  // attempts: 5,                      // override default per-job
});

// delayed
await emailsQueue.add('reminder', { id }, { delay: 24 * 3600 * 1000 });

// repeatable
await emailsQueue.add('digest', {}, {
  repeat: { pattern: '0 9 * * *', tz: 'America/New_York' },
  jobId: 'digest',                    // dedupe across restarts
});
```

`jobId` for idempotency: BullMQ refuses duplicate IDs. Otherwise the queue is at-least-once.

## Worker (separate process)

```typescript
// src/queue/workers/email.worker.ts
import { Worker, Job } from 'bullmq';
import { connection } from '../connection';
import { logger } from '../../lib/logger';
import { mailer } from '../../integrations/mailer';
import { db } from '../../db/client';

interface WelcomeJob { userId: string; }

const worker = new Worker(
  'emails',
  async (job: Job) => {
    switch (job.name) {
      case 'welcome': return handleWelcome(job.data as WelcomeJob);
      case 'reminder': return handleReminder(job.data);
      default: throw new Error(`unknown job: ${job.name}`);
    }
  },
  {
    connection,
    concurrency: 10,
    limiter: { max: 50, duration: 60_000 },   // rate limit: 50/min
  },
);

worker.on('failed', (job, err) =>
  logger.error({ err, jobId: job?.id, name: job?.name, attempts: job?.attemptsMade }, 'job failed'),
);
worker.on('completed', (job) =>
  logger.debug({ jobId: job.id, name: job.name }, 'job completed'),
);

async function handleWelcome({ userId }: WelcomeJob) {
  const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
  if (!user || user.welcomeSentAt) return;     // idempotent
  await mailer.sendWelcome(user.email);
  await db.update(users).set({ welcomeSentAt: new Date() }).where(eq(users.id, userId));
}

const shutdown = async () => {
  logger.info('worker shutting down');
  await worker.close();
  await connection.quit();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

Run:

```bash
node dist/queue/workers/email.worker.js
```

Or with PM2:

```javascript
{
  name: '{{project-slug}}-worker-emails',
  script: 'dist/queue/workers/email.worker.js',
  instances: 2,
  exec_mode: 'fork',
  kill_timeout: 30000,
}
```

## Concurrency tuning

| Workload | Concurrency |
|----------|-------------|
| CPU-bound (image processing, PDF) | ≤ CPU count |
| IO-bound (HTTP, DB) | 10–50, watch downstream limits |
| Heavy long jobs (exports) | 1–4 |

A worker with `concurrency: 10` and 2 PM2 instances = 20 in-flight jobs at once.

## Repeatable jobs

```typescript
// at app boot — safe to call repeatedly because of jobId
await emailsQueue.add('digest', {}, {
  repeat: { pattern: '0 9 * * *' },
  jobId: 'digest-cron',
});
```

To remove:

```typescript
const repeatable = await emailsQueue.getRepeatableJobs();
for (const j of repeatable) await emailsQueue.removeRepeatableByKey(j.key);
```

## Flow producers (multi-stage workflows)

```typescript
import { FlowProducer } from 'bullmq';

const flow = new FlowProducer({ connection });

await flow.add({
  name: 'process-order',
  queueName: 'orders',
  data: { orderId },
  children: [
    { name: 'validate', queueName: 'validation', data: { orderId } },
    { name: 'charge', queueName: 'billing', data: { orderId } },
    { name: 'fulfill', queueName: 'fulfillment', data: { orderId } },
  ],
});
```

Parent runs after all children complete. Children process in parallel.

For sequential dependencies (B depends on A's output), use `childrenValues` in the parent processor:

```typescript
new Worker('orders', async (job) => {
  const childResults = await job.getChildrenValues();
  // ...
});
```

## Bull Board (web UI)

```bash
pnpm add @bull-board/api @bull-board/express
```

```typescript
// for Express
import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter } from '@bull-board/express';
import { emailsQueue, billingQueue } from './queues';

const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath('/admin/queues');

createBullBoard({
  queues: [new BullMQAdapter(emailsQueue), new BullMQAdapter(billingQueue)],
  serverAdapter,
});

app.use('/admin/queues', requireAdminMiddleware, serverAdapter.getRouter());
```

**Always behind auth in prod** — Bull Board lets you drain queues.

## Observability

### Sentry

```typescript
import * as Sentry from '@sentry/node';

worker.on('failed', (job, err) => {
  Sentry.captureException(err, {
    tags: { queue: job?.queueName, job_name: job?.name, job_id: job?.id },
    extra: { data: job?.data, attempts: job?.attemptsMade },
  });
});
```

### OpenTelemetry

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  serviceName: '{{project-slug}}-worker-emails',
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

The `ioredis` instrumentation traces Redis operations; pair with manual spans inside `process()` for the actual work.

## Idempotency patterns

Same as Celery (see `celery.md`):

1. **Database flag**: check `welcomeSentAt` before sending
2. **Idempotency key**: caller provides UUID; worker stores it in Redis with `SET NX EX`
3. **State machine**: only act if state is the expected `from`

## Common pitfalls

Same as the patterns in `backend/nestjs/05-bullmq-queues.md`. Quick recap:

| Pitfall | Fix |
|---------|-----|
| Worker doesn't pick up jobs | Queue name typo — match exactly |
| `maxRetriesPerRequest must be null` | Set in IORedis options |
| Jobs accumulate forever | `removeOnComplete` + `removeOnFail` |
| Dup jobs after restart | Use `jobId` for repeatables |
| Slow jobs starve fast ones | Split into separate queues |
| OOM in worker | Lower concurrency or process in batches |
| Lost jobs on deploy | Long `kill_timeout`; graceful shutdown handler |
| `JobLockExtension` errors | Job took longer than lock — increase `stalledInterval` or speed up |
| Bull Board exposed | Always behind auth |

## When to outgrow BullMQ

- **Cross-language consumers**: Redis Streams or Kafka
- **Workflows with state**: Temporal / Inngest
- **Massive scale (millions of jobs/min)**: Kafka with custom consumers
- **Strict ordered processing per partition**: Kafka
