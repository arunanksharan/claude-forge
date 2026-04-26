# BullMQ Background Jobs

> Queue setup, processors, repeatable jobs, flow producers. Why BullMQ over alternatives.

## Why BullMQ

| Option | Verdict |
|--------|---------|
| **BullMQ** | Pick this. Active development, TypeScript-native, Redis-backed, supports flows/repeatable/delayed jobs. |
| `bull` (classic) | Deprecated. Same author, BullMQ is the rewrite. |
| `bee-queue` | Smaller community, fewer features. |
| `agenda` | MongoDB-based. Fine if you don't have Redis. |
| RabbitMQ + amqplib | Heavier ops cost. Worth it for cross-language fan-out, otherwise overkill. |
| Kafka | Way overkill for typical job queues. Use only if you have Kafka already. |

For typical Nest apps with a Redis already running: **BullMQ via `@nestjs/bullmq`**.

## Install

```bash
pnpm add @nestjs/bullmq bullmq ioredis
```

## QueueModule

```typescript
// src/queue/queue.module.ts
import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigService } from '@nestjs/config';
import { EmailProcessor } from './processors/email.processor';
import { BillingProcessor } from './processors/billing.processor';

@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: {
          url: config.get<string>('REDIS_URL'),
          maxRetriesPerRequest: null,   // required by BullMQ
        },
        defaultJobOptions: {
          removeOnComplete: { age: 24 * 3600, count: 1000 },  // keep 24h or 1000 jobs
          removeOnFail: { age: 7 * 24 * 3600 },                // keep failures 7d
          attempts: 3,
          backoff: { type: 'exponential', delay: 5000 },
        },
      }),
    }),
    BullModule.registerQueue(
      { name: 'emails' },
      { name: 'billing' },
      { name: 'long' },
    ),
  ],
  providers: [EmailProcessor, BillingProcessor],
  exports: [BullModule],
})
export class QueueModule {}
```

### Why these defaults

| Setting | Why |
|---------|-----|
| `removeOnComplete: { age, count }` | Don't accumulate indefinitely — Redis fills up |
| `removeOnFail: { age: 7d }` | Keep failures longer so you can investigate |
| `attempts: 3` | Reasonable retry default; override per job for special cases |
| `backoff: exponential, 5000` | 5s, 10s, 20s — gives transient failures time to clear |
| `maxRetriesPerRequest: null` | Required by BullMQ since 5.0 |

## Adding jobs

Inject the queue and call `add`:

```typescript
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';

@Injectable()
export class UsersService {
  constructor(@InjectQueue('emails') private emailsQueue: Queue) {}

  async register(email: string, password: string) {
    const user = await this.prisma.user.create({ data: { email, hashedPassword: await bcrypt.hash(password, 12) } });
    await this.emailsQueue.add('welcome', { userId: user.id }, {
      delay: 0,
      jobId: `welcome:${user.id}`,   // idempotency: dedupe
    });
    return user;
  }
}
```

### Job IDs for idempotency

Set `jobId` if you want "at most once" semantics. BullMQ refuses to add a job with a duplicate ID. Otherwise it's "at least once" — workers may process the same job more than once on retry, so **make processors idempotent**.

## Processor

```typescript
// src/queue/processors/email.processor.ts
import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { MailerService } from '../../integrations/mailer.service';
import { UsersService } from '../../users/users.service';

interface WelcomeJob {
  userId: string;
}

@Processor('emails', { concurrency: 10 })
export class EmailProcessor extends WorkerHost {
  private readonly log = new Logger(EmailProcessor.name);

  constructor(
    private readonly mailer: MailerService,
    private readonly users: UsersService,
  ) { super(); }

  async process(job: Job<WelcomeJob>): Promise<void> {
    switch (job.name) {
      case 'welcome':
        return this.handleWelcome(job);
      default:
        throw new Error(`unknown job: ${job.name}`);
    }
  }

  private async handleWelcome(job: Job<WelcomeJob>) {
    const user = await this.users.findById(job.data.userId);
    if (!user) {
      this.log.warn(`welcome: user not found ${job.data.userId}`);
      return;  // idempotent: nothing to do
    }
    await this.mailer.sendWelcome(user.email);
  }

  @OnWorkerEvent('failed')
  onFailed(job: Job, err: Error) {
    this.log.error(`job ${job.id} ${job.name} failed: ${err.message}`, err.stack);
  }

  @OnWorkerEvent('completed')
  onCompleted(job: Job) {
    this.log.debug(`job ${job.id} ${job.name} completed`);
  }
}
```

### Concurrency

`{ concurrency: 10 }` — this worker processes 10 jobs in parallel. Tune per workload:

- **CPU-bound** (image resize, PDF gen): set ≤ number of cores
- **IO-bound** (HTTP, DB): higher (10–50), but watch your downstream limits
- **Heavy jobs** (long-running export): low (1–4) so one worker doesn't hog all the slots

## Queues — split by SLA

Don't dump everything in one queue. Split by SLA:

| Queue | Concurrency | Workers | Notes |
|-------|-------------|---------|-------|
| `emails` | 10 | 2 | Many small fast jobs |
| `billing` | 4 | 1 | External API calls; need rate limit |
| `long` | 1 | 1 | Hours-long exports; one at a time |

A clogged-up `long` queue then doesn't starve your emails.

## Repeatable jobs (cron-like)

```typescript
await this.emailsQueue.add(
  'daily-digest',
  { date: today() },
  {
    repeat: { pattern: '0 9 * * *', tz: 'America/New_York' },  // 9am daily
    jobId: 'daily-digest',  // dedupe across restarts
  },
);
```

Or one-time delayed:

```typescript
await this.emailsQueue.add('reminder', { id }, { delay: 24 * 3600 * 1000 });
```

**Repeatable jobs survive restarts** — they're stored in Redis. Add them once at startup. To clean up:

```typescript
const repeatable = await queue.getRepeatableJobs();
for (const job of repeatable) {
  await queue.removeRepeatableByKey(job.key);
}
```

## Flow producers — multi-stage workflows

When job B depends on job A's result:

```typescript
import { FlowProducer } from 'bullmq';

const flowProducer = new FlowProducer({ connection });

await flowProducer.add({
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

The parent `process-order` runs after all children complete. Children process in parallel.

## Rate limiting

Cap requests to a downstream:

```typescript
new Worker('emails', processor, {
  connection,
  limiter: { max: 100, duration: 60_000 },  // 100 jobs per minute
});
```

## Monitoring with Bull Board

```bash
pnpm add @bull-board/api @bull-board/express @bull-board/nestjs
```

```typescript
// src/queue/bull-board.module.ts
import { BullBoardModule } from '@bull-board/nestjs';
import { ExpressAdapter } from '@bull-board/express';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';

BullBoardModule.forRoot({
  route: '/queues',
  adapter: ExpressAdapter,
}),
BullBoardModule.forFeature({
  name: 'emails',
  adapter: BullMQAdapter,
}),
```

Now `http://localhost:{{api-port}}/queues` shows job state, retry, etc. **Lock this behind auth in prod** (it can drain queues).

## Graceful shutdown

```typescript
// main.ts
app.enableShutdownHooks();
```

NestJS will fire `OnModuleDestroy` on all providers. The BullMQ workers close connections, finish in-flight jobs, then exit. **Don't `kill -9`** — you'll lose work.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Worker doesn't pick up jobs | Check `Processor('queue-name')` matches `BullModule.registerQueue({ name: ... })` exactly |
| `maxRetriesPerRequest must be null` error | Set `connection: { maxRetriesPerRequest: null }` |
| Jobs in Redis accumulate forever | Set `removeOnComplete` and `removeOnFail` |
| Repeated jobs duplicate after restart | Use `jobId` to dedupe |
| Slow jobs block fast ones | Split into separate queues |
| OOM in worker | Lower concurrency, or process in batches inside the job |
| Lost jobs on deploy | `enableShutdownHooks()` + give workers time (30+ sec) |
| Race when adding jobs from API + processing them in worker | They communicate via Redis — no app-level race |
| `JobLockExtension` errors | Worker held the job past its lock duration. Increase `stalledInterval` or speed up the job. |
| Can't see jobs in Bull Board | Adapter needs to register *each queue* via `forFeature` |
