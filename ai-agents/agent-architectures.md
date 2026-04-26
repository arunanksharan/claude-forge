# Agent Architectures

> ReAct, plan-execute, reflection, multi-agent. When each pattern wins, when it doesn't.

## "Agent" — narrowed definition

For this guide: an **agent** is an LLM that takes actions in the world (tool calls / API calls / code execution), observes results, and decides what to do next — in a loop.

If your "agent" is a single prompt + completion, it's not an agent. It's a prompt. Don't add agent ceremony.

## When you actually need an agent

| Problem shape | Pick |
|---------------|------|
| Translate a prompt to a SQL query | Single LLM call (no agent) |
| Answer a question with retrieval | RAG (`rag-patterns.md`) |
| Compose a workflow with branching based on data | Tool-using agent |
| Multi-step task where the model needs to react to intermediate results | Tool-using agent (ReAct) |
| Long-running multi-step business process | Temporal/Inngest with LLM nodes (not pure agent) |
| Multiple distinct skill-sets coordinating | Multi-agent (carefully) |

## Pattern 1 — ReAct (Reason + Act)

The classical agent loop:

```
loop:
  reasoning = LLM("given history, what should I do next?")
  if reasoning.action == "answer":
    return reasoning.answer
  observation = execute_tool(reasoning.action)
  history.append({reasoning, observation})
```

Modern function-calling APIs (OpenAI, Anthropic) make this trivial:

```python
from anthropic import Anthropic
client = Anthropic()

def run_agent(user_query: str, tools: list[dict], max_steps: int = 10):
    messages = [{"role": "user", "content": user_query}]

    for step in range(max_steps):
        resp = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            tools=tools,
            messages=messages,
        )

        # check for tool use
        if resp.stop_reason == "end_turn":
            return resp.content

        # collect tool uses, execute, append results
        tool_uses = [b for b in resp.content if b.type == "tool_use"]
        if not tool_uses:
            return resp.content

        messages.append({"role": "assistant", "content": resp.content})
        tool_results = []
        for tool in tool_uses:
            result = TOOLS[tool.name](**tool.input)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tool.id,
                "content": json.dumps(result),
            })
        messages.append({"role": "user", "content": tool_results})

    raise RuntimeError(f"agent exceeded {max_steps} steps")
```

### ReAct best practices

| | |
|---|---|
| **Always set `max_steps`** | Prevents infinite loops; 10–20 is usually enough |
| **Set max cost too** (sum tokens × price) | Hard cap to avoid bill shock |
| **Stream and inspect intermediate steps** | For debugging + observability |
| **Make tools idempotent** | Agent may retry on partial failure |
| **Tool errors → return as observation, don't crash** | Let the model recover |
| **Cap individual tool result size** | Otherwise context fills up after a few steps |

## Pattern 2 — Plan + Execute

For tasks where the structure is known up front:

```
1. Planner LLM: "Given the goal, output a JSON plan of steps"
2. For each step: Executor LLM (or deterministic code) runs it
3. (Optional) Reviewer LLM: "Did we accomplish the goal?"
```

```python
plan = planner_llm(goal)
# plan = {"steps": [{"tool": "search", "args": {...}}, {"tool": "summarize", "args": {...}}]}

results = []
for step in plan["steps"]:
    results.append(TOOLS[step["tool"]](**step["args"]))

answer = reviewer_llm(goal, plan, results)
```

### When plan + execute beats ReAct

- The plan is **knowable up front** (most workflows)
- You want **predictable cost** (one planner call, then deterministic)
- You want **resumability** (Temporal-style — pause between steps)
- You're **less worried about adapting** to unexpected intermediate results

ReAct adapts to surprises better. Plan + Execute is cheaper and more predictable.

## Pattern 3 — Reflection

After producing an answer, ask the model to critique itself:

```python
draft = llm(query)
critique = llm(f"Critique this answer for accuracy and completeness:\n{draft}")
final = llm(f"Improve the answer based on the critique:\nDraft: {draft}\nCritique: {critique}")
```

Useful for:
- Code generation (catch bugs in the draft)
- Long-form writing (catch contradictions)
- Math / reasoning (verify steps)

Cost: ~3x. Quality bump: real, but diminishing returns. Test with your evals.

## Pattern 4 — Multi-agent

Multiple LLMs with distinct system prompts collaborating. Common shapes:

### Supervisor + workers

```
Supervisor LLM ("decide which specialist to call")
  ├── Code agent
  ├── Search agent
  └── Math agent
```

Each worker is itself a tool-using agent. Supervisor delegates by tool call.

### Pipeline (sequential specialists)

```
Researcher → Writer → Editor → Fact-checker
```

Each consumes the previous output, augments, passes on.

### Debate / consensus

```
Two agents argue both sides → judge agent decides
```

Useful for adversarial domains. Often overkill.

### Honest assessment

Multi-agent is **almost always premature**. Reasons it disappoints:

- More LLM calls = more cost + more latency
- Coordination errors (one agent misunderstands another)
- Harder to debug (which agent caused the failure?)
- Harder to evaluate (need eval per agent + end-to-end)

**Try single-agent + better tools / better prompt first.** Move to multi-agent only when single-agent has measurable ceiling on your evals.

## Pattern 5 — Durable agents (Temporal / Inngest)

For long-running multi-step processes (hours / days), pure in-memory agent loops fail:

- Process restarts lose state
- No retries on transient failures
- Can't pause mid-flow for human approval

Move to **durable execution**:

```python
@workflow.defn
class ResearchAgentWorkflow:
    @workflow.run
    async def run(self, query: str) -> str:
        plan = await workflow.execute_activity(generate_plan, query, ...)
        for step in plan.steps:
            result = await workflow.execute_activity(run_step, step, ...)
            # workflow auto-checkpoints — survives crashes
        return await workflow.execute_activity(synthesize, plan, results, ...)
```

Each `execute_activity` is a durable checkpoint. Worker dies mid-flow → resumes from last checkpoint.

For agents that take >5 minutes or need human-in-the-loop: Temporal / Inngest, not raw asyncio.

## Cost + latency budgets

Agents can blow up:
- A 10-step ReAct loop with Claude Opus = ~$1+ per query if not careful
- Multi-agent x 4 agents x 5 steps each = 20 LLM calls

**Budget per request**:
- **Hard cap on steps** (10–20)
- **Hard cap on cost** (sum tokens × price; abort if exceeded)
- **Model routing** — use cheaper models for sub-tasks (Haiku for tool selection, Sonnet for final answer)
- **Caching** — `prompt_caching` on Anthropic / `prompt_cache_key` on OpenAI for repeated system prompts

## Observability (critical)

You can't iterate on agents without seeing what they do. Instrument with:

- **Langfuse** (`observability/04-langfuse.md`) — every LLM call is a trace; tool calls are spans; full step-by-step replay
- **OpenTelemetry** spans per tool call
- **Sentry** for errors

Without observability you'll have agents that work 80% of the time and you'll have no idea why.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Infinite loop (model keeps calling tools) | Hard `max_steps`; verify each loop progresses |
| Cost explosion | Hard cost cap; prefer cheaper models for sub-steps |
| Tool result too large → context fills up | Truncate / summarize results before returning |
| Agent confidently lies (hallucinates tool result) | Use real tool calls only; never let model "imagine" a tool result |
| Tool description lies | "Searches the web" actually searches a closed corpus → unreliable. Be honest. |
| State lost on crash (long-running) | Move to Temporal / Inngest |
| One bad tool poisons the agent | Validate tool outputs; surface errors as observations |
| Multi-agent confusion (who decides what) | Start with single-agent; add complexity only when measurably better |
| No evals → can't tell if changes help | Build a small eval set BEFORE iterating on prompts |
| Prompt injection through tool results | Treat tool outputs (especially web search) as untrusted; tell the model so |
