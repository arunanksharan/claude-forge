# Next.js — claudeforge guides

Opinionated, production-grade Next.js (and React) blueprints. Written for Next.js 15+ on React 19, but most content applies to React 18 + Vite as well.

## Files in this folder

| File | What it is | Read when |
|------|-----------|-----------|
| [`01-stack-and-libraries.md`](./01-stack-and-libraries.md) | Library evaluation — what to use, what to reject, with bundle sizes and reasoning | Picking dependencies for a new app |
| [`02-design-system-spec.md`](./02-design-system-spec.md) | Full design system spec: token architecture, color philosophy, motion, components | Building or extending a design system |
| [`03-animations-and-motion.md`](./03-animations-and-motion.md) | Framer Motion patterns, scroll-linked, route transitions | Adding rich motion |
| [`04-mobile-responsive.md`](./04-mobile-responsive.md) | Mobile-first responsive strategy, touch targets, viewport, safe area | Mobile / responsive work |
| [`05-forms-and-state.md`](./05-forms-and-state.md) | react-hook-form + zod, TanStack Query, Zustand, URL state | Building forms or data flows |
| [`06-testing-with-chrome-devtools-mcp.md`](./06-testing-with-chrome-devtools-mcp.md) | Vitest + Playwright + agent-driven E2E via MCP | Writing tests |
| [`PROMPT.md`](./PROMPT.md) | The meta-prompt: paste into Claude Code to scaffold a new project | Starting a new app |

## Quick decision summary

If you only read the headers:

- **Components:** shadcn/ui (Radix + CVA + Tailwind). Not Mantine, not antd, not MUI.
- **State:** Zustand client-side, TanStack Query server-side.
- **Forms:** react-hook-form + zod.
- **Animation:** framer-motion. Not React Spring.
- **Icons:** lucide-react. Not react-icons.
- **Toast:** sonner. Not react-hot-toast.
- **Charts:** Recharts (via shadcn charts).
- **Tables:** TanStack Table v8.
- **Dates:** date-fns.

The full reasoning is in `01-stack-and-libraries.md`.
