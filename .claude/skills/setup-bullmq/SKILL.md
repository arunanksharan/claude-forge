---
name: setup-bullmq
description: Use when the user wants to add BullMQ (Node background jobs with Redis) to a NestJS / Express / Node app — queues, workers as separate processes, processors, repeatable jobs, flow producers, Bull Board admin UI. Triggers on "add background jobs", "add bullmq", "node queue", "nestjs bullmq".
---

# Set Up BullMQ for Background Jobs (claudeforge)

Follow `async-and-queues/bullmq.md` and `backend/nestjs/05-bullmq-queues.md` (Nest-specific) or `backend/nodejs-express/05-bullmq-workers.md` (Express). Steps:

1. **Confirm with user**:
   - Stack: Nest or plain Express?
   - Already have Redis? If not, set up via Docker compose.
   - Use cases: emails, billing, scheduled, long-running?
2. **Install + configure**:
   - Nest: `pnpm add @nestjs/bullmq bullmq ioredis`
   - Express: `pnpm add bullmq ioredis`
   - Create `queue/connection.ts` with the IORedis instance (`maxRetriesPerRequest: null` is required by BullMQ)
3. **Define queues** (`queue/queues.ts`):
   - One Queue per SLA group (`emails`, `billing`, `long`)
   - `defaultJobOptions: { removeOnComplete: { age, count }, removeOnFail: { age }, attempts: 3, backoff: { type: 'exponential', delay: 5000 } }`
4. **Define processors / workers**:
   - Nest: `@Processor('emails') class EmailProcessor extends WorkerHost { async process(job) { ... } }`
   - Express: `new Worker('emails', async (job) => {...}, { connection, concurrency })` in a separate file
   - **Idempotency**: every job handler checks state before mutating (DB flag, idempotency key, or natural)
   - Use `jobId` on `add()` for idempotent enqueueing
5. **Wire into the app**:
   - Inject `@InjectQueue('emails') private q: Queue` (Nest) or import the queue (Express)
   - `await q.add('welcome', { userId }, { jobId: \`welcome:${userId}\` })`
6. **Run workers**:
   - Run as **separate Node processes** (not inside the API process). For PM2: separate apps in ecosystem.config.cjs. For Docker Compose: separate `worker-*` service.
7. **Monitoring with Bull Board**:
   - Install `@bull-board/api` + `@bull-board/express` (or `@bull-board/nestjs`)
   - Mount under `/admin/queues` BEHIND auth + IP allowlist
8. **Repeatable jobs**: at boot, register cron-like jobs with `repeat: { pattern: '0 9 * * *' }` and `jobId: 'unique-id'` so they don't duplicate on restart.
9. **Observability**:
   - Sentry: `worker.on('failed', (job, err) => Sentry.captureException(err, { tags: { queue, job_name } }))`
   - OpenTelemetry: auto-instrumentation for ioredis covers most; add manual spans for the job body
10. **Verify**: enqueue a job from a route, observe it process, see it in Bull Board.

Workers as separate processes, not in the API. Always make handlers idempotent.
