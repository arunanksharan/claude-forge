# Tool Use / Function Calling

> Designing tools an LLM can call: schema, descriptions, error handling, security, and how to expose existing APIs as tools.

## The basic shape

```python
tools = [
    {
        "name": "search_users",
        "description": "Search users by email substring. Returns up to 50 matches.",
        "input_schema": {
            "type": "object",
            "properties": {
                "email_substring": {"type": "string", "description": "Case-insensitive email substring"},
                "active_only": {"type": "boolean", "description": "Only return active users", "default": True},
            },
            "required": ["email_substring"],
        },
    },
]

resp = client.messages.create(
    model="claude-sonnet-4-6",
    tools=tools,
    messages=[{"role": "user", "content": "find users with 'acme' in their email"}],
)
# resp.content includes a tool_use block with input={"email_substring": "acme"}
```

You execute the tool yourself, return the result back as a tool_result message, model continues.

The mechanics differ slightly between OpenAI and Anthropic SDKs but the design principles are identical.

## Tool design — the high-leverage decisions

### 1. Description is the prompt for that tool

The model only knows your tool from its description. Bad description → mis-use.

```python
# bad
{"name": "create_invoice", "description": "Creates an invoice"}

# good
{
    "name": "create_invoice",
    "description": (
        "Create a draft invoice for a customer. "
        "The invoice is created in 'draft' status — call `send_invoice` to actually send it. "
        "Validates that customer_id exists; raises if not. "
        "Currency is always USD. For other currencies, use `create_invoice_multi_currency`."
    ),
    ...
}
```

State:
- What it does (concretely)
- What it doesn't do (so the model doesn't expect it)
- Side effects (does it send email? charge cards?)
- Error conditions
- Related tools (so the model can chain)

### 2. Schema — be specific

```python
# bad
"product_ids": {"type": "array", "items": {"type": "string"}}

# good
"product_ids": {
    "type": "array",
    "items": {"type": "string", "pattern": "^prod_[a-zA-Z0-9]{16}$"},
    "minItems": 1,
    "maxItems": 100,
    "description": "Product IDs in the format 'prod_XXXXXXXXXXXXXXXX'. Get these from `search_products`."
}
```

The schema is checked by the SDK before your handler runs. Tighter schema = fewer invalid calls = less wasted money.

### 3. One tool per atomic operation

Don't make a `do_thing(action: "create" | "update" | "delete")` mega-tool. Three tools. The model picks correctly more reliably.

Exception: when the variants are truly variants of one operation (e.g. `search` with optional filters).

### 4. Return shape: structured + concise

```python
# bad — verbose, repetitive
{"status": "success", "data": {"users": [{"id": "u1", "email": "a@a.com", "created_at": "2025...", "first_name": "...", "last_name": "...", ...}]}}

# good — only what the model needs
{"users": [{"id": "u1", "email": "a@a.com"}], "count": 1, "more": False}
```

The model's context bloats with every tool result. Keep them tight. Include `more: True/False` so the model knows whether to paginate.

### 5. Error returns, not exceptions

If a tool fails, don't raise. **Return** the error so the model can see it and recover:

```python
def search_users_handler(email_substring: str, active_only: bool = True):
    try:
        results = users_repo.search_by_email(email_substring, active_only)
        return {"users": results, "count": len(results)}
    except DBConnectionError as e:
        return {"error": "database_unreachable", "message": str(e), "retry_suggested": True}
    except ValidationError as e:
        return {"error": "invalid_input", "message": str(e)}
```

The model sees the error, often retries with corrected input, or asks the user.

If a tool truly cannot be used (auth, hard down), raise — the agent loop handles it.

## Common tool patterns

### Search → fetch

```
search_users(query: str) → list of {id, summary}
get_user(id: str) → full record
```

The model searches first (cheap, listing), then fetches details for the few it cares about.

### Idempotent create with key

```
create_order(idempotency_key: str, items: list, customer_id: str)
```

If the model retries (or you re-run the agent), the same `idempotency_key` returns the same result instead of creating duplicates.

### Pagination

```
list_orders(cursor: str | None = None, limit: int = 20) → {orders: [...], next_cursor: str | None}
```

The model can decide "I need more" and call again with `cursor=next_cursor`. Don't return all results in one call — context blows up.

### Confirmation gates

For destructive ops (delete, charge), require a confirm step:

```
delete_user(id: str, confirm: bool = False)
  - if confirm=False: returns {"warning": "...", "to_delete": {...}, "call_again_with_confirm_true": True}
  - if confirm=True: actually deletes
```

The model calls once (sees what would happen), checks with the user if needed, calls again with confirm.

### Async / long-running

```
generate_report(params) → {"job_id": "abc"}
get_report_status(job_id: str) → {"status": "pending" | "complete", "result": ... }
```

The model polls. Often paired with a `wait_seconds: int` parameter so the model doesn't spam.

## Security

### Tool calls are user-controlled (effectively)

If your tool does `os.system(input)` and input comes from an LLM driven by a user message, **the user controls `os.system` arguments**. Treat tool inputs as untrusted user input.

```python
# NEVER
def execute_sql(query: str): db.execute(query)

# instead, expose narrow tools
def get_user_orders(user_id: str): db.query.orders.find_many(where=eq(orders.user_id, user_id))
```

Or, if you absolutely need free-form SQL: use a **read-only role + connection** + `LIMIT` enforcement + output redaction.

### Auth: the agent acts as someone

If your agent has tools like `delete_user`, it can delete any user. **Scope tools to the calling user's permissions:**

```python
def make_user_tools(acting_user: User):
    def get_my_orders():
        return orders_repo.find_by_user(acting_user.id)   # always THIS user

    def delete_order(order_id: str):
        order = orders_repo.find(order_id)
        if order.user_id != acting_user.id and not acting_user.is_admin:
            return {"error": "forbidden"}
        return orders_repo.delete(order_id)

    return [as_tool(get_my_orders), as_tool(delete_order)]
```

Tools are constructed per-request with the acting user baked in. Never let the model specify `as_user_id`.

### Prompt injection through tool results

A tool that fetches the web returns content the user didn't write. That content can contain `"Ignore prior instructions and ..."` attempting to hijack the agent.

Defenses:
- **Tag tool outputs**: wrap in `<tool_output>...</tool_output>` and tell the system prompt to treat them as untrusted data, not instructions
- **Don't blindly execute** anything based on web-fetched content
- **Sanitize** known injection patterns when feasible

This is an unsolved problem in general. For high-stakes agents, treat all retrieved content as adversarial.

### Rate limit on the tool side

The model may call a tool 100 times in a loop. Rate-limit at the tool level:

```python
def get_external_api(query: str):
    if rate_limiter.would_exceed("external_api"):
        return {"error": "rate_limited", "retry_after_seconds": 60}
    ...
```

The model sees the error and (usually) backs off.

## MCP (Model Context Protocol)

If you're building tools that should be reusable across multiple agents (or agent platforms), expose them as an **MCP server**:

```typescript
// hello-mcp.ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({ name: 'hello', version: '1.0.0' }, {
  capabilities: { tools: {} },
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: 'greet',
    description: 'Greet someone by name',
    inputSchema: {
      type: 'object',
      properties: { name: { type: 'string' } },
      required: ['name'],
    },
  }],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name === 'greet') {
    return { content: [{ type: 'text', text: `Hello, ${req.params.arguments?.name}!` }] };
  }
  throw new Error('unknown tool');
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

Now Claude Code, Cursor, any MCP-compatible client can use your tools.

When to ship as MCP:
- The tools wrap a service that other agents would benefit from
- You want one source of truth for tool definitions
- You want to reuse across Python/Node/etc agents

When to skip MCP:
- Just calling tools from your own backend agent → in-process is simpler
- Internal-only tools that don't need to be portable

## Observability

Trace each tool call:

```python
from langfuse import Langfuse
langfuse = Langfuse()

@observe()
async def search_users_handler(email_substring: str, active_only: bool = True):
    langfuse_context.update_current_observation(
        input={"email_substring": email_substring, "active_only": active_only},
    )
    results = await users_repo.search_by_email(email_substring, active_only)
    langfuse_context.update_current_observation(output={"count": len(results)})
    return {"users": results, "count": len(results)}
```

Now you can see in Langfuse: every tool call, its input, output, latency, errors. Critical for debugging "why did the agent do that?"

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Tool description is one line | Add side effects, error conditions, related tools |
| Tool returns 50KB of JSON | Truncate / paginate; the model's context fills up fast |
| Tool raises instead of returning error | Return `{"error": "...", "message": "..."}` so model can recover |
| Model hallucinates that a tool exists | Tighten the system prompt: "You MAY ONLY call the tools listed above." |
| Same tool called 20 times in a row | Likely a missing termination condition; max_steps + better description |
| Permissions leak (model deletes others' data) | Scope tools to acting user; never trust user_id from model input |
| Prompt injection from tool output | Tag tool outputs as untrusted; don't execute based on them |
| Cost spike from agentic retrieval loop | Cap iterations + cost per request |
| Tool schema too permissive | Tight schemas (regex, min/max) reduce invalid calls |
| Forget to return on confirmation flow | Two-step pattern: first call returns "would do X, confirm?", second call (with confirm=True) does it |
