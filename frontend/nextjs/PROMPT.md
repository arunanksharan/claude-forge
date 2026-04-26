# Next.js Project — Master Scaffold Prompt

> **Copy this entire file into Claude Code (or any LLM). Replace `{{placeholders}}`. The model scaffolds a production-grade Next.js project with the locked stack from `01-stack-and-libraries.md`.**

---

## Context for the model

You are scaffolding a new Next.js 15+ project on React 19, with the Avashi-style design system principles from this folder. Your job is to set up the project structure, install only the approved libraries from `01-stack-and-libraries.md`, wire up shadcn/ui, and create a representative example page demonstrating the patterns.

If something is ambiguous, **ask once, then proceed**.

## Project parameters

```
project_name:       {{project-name}}
project_slug:       {{project-slug}}            # kebab-case
description:        {{one-line-description}}
app_type:           {{web|admin|landing|chat}}  # affects which extras to install
include_auth:       {{yes-or-no}}               # NextAuth/Clerk integration
include_3d:         {{yes-or-no}}               # Three.js + R3F
brand_primary_hex:  {{hex}}                     # e.g. #8b5cf6
deployment_target:  {{vercel|self-hosted}}      # affects Dockerfile + standalone build
```

---

## Locked stack (from `01-stack-and-libraries.md`)

| Concern | Pick |
|---------|------|
| Framework | **Next.js 15+ (App Router)** on **React 19** |
| Package manager | **pnpm** |
| TypeScript | **5.6+ strict** |
| Components | **shadcn/ui** (Radix + CVA + Tailwind 4) |
| Styling | **Tailwind CSS 4** + CSS variables |
| Icons | **lucide-react** |
| State (client) | **zustand** |
| State (server) | **TanStack Query v5** |
| Forms | **react-hook-form** + **zod** + **@hookform/resolvers** |
| Animation | **framer-motion** |
| Toast | **sonner** |
| Dates | **date-fns** |
| Markdown | **react-markdown** + **remark-gfm** |
| Tables (admin) | **TanStack Table v8** |
| Charts (admin) | **Recharts** (via shadcn/ui charts) |
| Typography | **Geist** (Sans + Mono) |
| Linting | **ESLint flat config** + **Prettier** + **Tailwind plugin** |
| Testing | **Vitest** + **React Testing Library** + **Playwright** for E2E |

## Rejected (see `01-stack-and-libraries.md` section 7)

`antd`, `@lobehub/ui`, `chakra-ui`, `mantine`, `material-ui`, `styled-components`, `emotion`, `react-icons`, `formik`, `lenis`, `ogl`, `moment`, `dayjs`.

---

## Directory layout

```
{{project-slug}}/
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
├── next.config.ts                  # standalone output if self-hosted
├── tailwind.config.ts
├── postcss.config.mjs
├── eslint.config.mjs               # flat config
├── .prettierrc.mjs
├── .env.example
├── .gitignore
├── components.json                 # shadcn/ui config
├── Dockerfile                      # if self-hosted
├── docker-compose.dev.yml
├── README.md
├── public/
│   └── fonts/
├── src/
│   ├── app/                        # App Router
│   │   ├── layout.tsx              # root layout, fonts, providers
│   │   ├── page.tsx                # home
│   │   ├── globals.css             # Tailwind directives + CSS vars
│   │   ├── (marketing)/            # route groups
│   │   ├── (app)/                  # authed routes
│   │   │   ├── layout.tsx          # app shell
│   │   │   └── dashboard/
│   │   │       └── page.tsx
│   │   └── api/
│   │       └── health/route.ts
│   ├── components/
│   │   ├── ui/                     # shadcn/ui copies (Button, Input, etc.)
│   │   ├── layout/                 # Header, Sidebar, Footer
│   │   └── features/
│   │       └── {{feature}}/
│   │           ├── {{feature}}-form.tsx
│   │           └── {{feature}}-list.tsx
│   ├── lib/
│   │   ├── utils.ts                # cn() helper
│   │   ├── api-client.ts           # TanStack Query client + fetch wrapper
│   │   ├── env.ts                  # zod-validated env
│   │   └── format.ts               # date/number formatters
│   ├── stores/                     # zustand stores
│   │   └── ui-store.ts             # ui-only state (sidebar open, theme)
│   ├── hooks/
│   │   ├── use-media-query.ts
│   │   └── use-debounce.ts
│   └── types/
│       └── api.ts                  # shared API types (or generated)
└── tests/
    ├── unit/
    └── e2e/
        └── playwright.config.ts
```

## Key conventions

- **Server Components by default**, `"use client"` only when needed (state, effects, browser APIs)
- **Colocate** server actions, route handlers, and components per feature when small; split into `lib/` only when reused
- **Use route groups** `(marketing)`, `(app)` for distinct layouts without affecting URLs
- **Don't put data fetching in Client Components** — fetch in Server Components, pass as props, or use TanStack Query for client-side mutations
- **Suspense + Streaming** for slow data — wrap with `<Suspense fallback>` and a `loading.tsx`

---

## Key files

### `package.json`

```json
{
  "name": "{{project-slug}}",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev --turbo",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "format": "prettier --write \"src/**/*.{ts,tsx,css}\"",
    "test": "vitest run",
    "test:watch": "vitest",
    "e2e": "playwright test",
    "type-check": "tsc --noEmit"
  },
  "dependencies": {
    "next": "^15",
    "react": "^19",
    "react-dom": "^19",
    "tailwindcss": "^4",
    "class-variance-authority": "^0.7",
    "clsx": "^2",
    "tailwind-merge": "^2",
    "lucide-react": "^0.460",
    "geist": "^1.3",
    "framer-motion": "^11",
    "sonner": "^1.7",
    "zustand": "^5",
    "@tanstack/react-query": "^5",
    "react-hook-form": "^7",
    "zod": "^3.23",
    "@hookform/resolvers": "^3",
    "date-fns": "^4",
    "react-markdown": "^9",
    "remark-gfm": "^4",
    "@tailwindcss/typography": "^0.5",
    "@radix-ui/react-slot": "^1",
    "@radix-ui/react-dialog": "^1",
    "@radix-ui/react-dropdown-menu": "^2",
    "@radix-ui/react-tooltip": "^1",
    "@radix-ui/react-tabs": "^1",
    "@radix-ui/react-label": "^2"
  },
  "devDependencies": {
    "@types/node": "^22",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "typescript": "^5.6",
    "@tailwindcss/postcss": "^4",
    "postcss": "^8",
    "eslint": "^9",
    "eslint-config-next": "^15",
    "@typescript-eslint/eslint-plugin": "^8",
    "@typescript-eslint/parser": "^8",
    "prettier": "^3",
    "prettier-plugin-tailwindcss": "^0.6",
    "vitest": "^2",
    "@vitejs/plugin-react": "^4",
    "@testing-library/react": "^16",
    "@testing-library/jest-dom": "^6",
    "@testing-library/user-event": "^14",
    "jsdom": "^25",
    "@playwright/test": "^1.48"
  }
}
```

### `src/app/layout.tsx`

```tsx
import type { Metadata } from 'next';
import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import { Toaster } from 'sonner';
import { Providers } from './providers';
import './globals.css';

export const metadata: Metadata = {
  title: '{{project-name}}',
  description: '{{one-line-description}}',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <body className="bg-surface-base text-text-primary font-sans antialiased">
        <Providers>{children}</Providers>
        <Toaster richColors closeButton />
      </body>
    </html>
  );
}
```

### `src/app/providers.tsx`

```tsx
'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            refetchOnWindowFocus: false,
            retry: 1,
          },
        },
      }),
  );

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}
```

### `src/lib/utils.ts`

```tsx
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### `src/lib/env.ts`

```tsx
import { z } from 'zod';

const envSchema = z.object({
  NEXT_PUBLIC_API_URL: z.string().url(),
  NEXT_PUBLIC_APP_URL: z.string().url(),
});

const result = envSchema.safeParse({
  NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
  NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
});

if (!result.success) {
  throw new Error('Invalid env: ' + JSON.stringify(result.error.flatten().fieldErrors));
}

export const env = result.data;
```

### `tailwind.config.ts`

See `02-design-system-spec.md` for the full token system. The minimal version:

```typescript
import type { Config } from 'tailwindcss';

export default {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // semantic tokens consumed via CSS variables in globals.css
        surface: {
          base: 'rgb(var(--color-surface-base) / <alpha-value>)',
          raised: 'rgb(var(--color-surface-raised) / <alpha-value>)',
          overlay: 'rgb(var(--color-surface-overlay) / <alpha-value>)',
        },
        text: {
          primary: 'rgb(var(--color-text-primary) / <alpha-value>)',
          secondary: 'rgb(var(--color-text-secondary) / <alpha-value>)',
          tertiary: 'rgb(var(--color-text-tertiary) / <alpha-value>)',
        },
        brand: {
          DEFAULT: 'rgb(var(--color-brand) / <alpha-value>)',
          fg: 'rgb(var(--color-brand-fg) / <alpha-value>)',
        },
      },
      fontFamily: {
        sans: ['var(--font-geist-sans)', 'sans-serif'],
        mono: ['var(--font-geist-mono)', 'monospace'],
      },
    },
  },
  plugins: [require('@tailwindcss/typography')],
} satisfies Config;
```

### `src/app/globals.css`

```css
@import 'tailwindcss';

@layer base {
  :root {
    /* dark by default — see 02-design-system-spec.md for the full palette */
    --color-surface-base:    13 13 10;
    --color-surface-raised:  26 26 22;
    --color-surface-overlay: 38 38 31;
    --color-text-primary:    244 244 242;
    --color-text-secondary:  168 168 163;
    --color-text-tertiary:   113 113 108;
    --color-brand:           139 92 246;
    --color-brand-fg:        255 255 255;
  }

  .light {
    --color-surface-base:    255 255 255;
    --color-surface-raised:  248 248 246;
    /* ... */
  }
}
```

### `components.json` (shadcn/ui)

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsc": true,
  "tsx": true,
  "tailwind": {
    "config": "tailwind.config.ts",
    "css": "src/app/globals.css",
    "baseColor": "slate",
    "cssVariables": true,
    "prefix": ""
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui",
    "lib": "@/lib",
    "hooks": "@/hooks"
  }
}
```

After init, add components on demand:

```bash
pnpx shadcn@latest add button input label dialog dropdown-menu tooltip tabs toast
```

---

## Generation steps

1. **Confirm parameters.**
2. **Run `pnpm create next-app@latest {{project-slug}} --ts --tailwind --eslint --src-dir --app --import-alias "@/*"`.**
3. **Replace `package.json` deps** with the locked stack above.
4. **`pnpm install`.**
5. **Initialize shadcn/ui:** `pnpx shadcn@latest init` (default options).
6. **Install initial components:** Button, Input, Label, Dialog, Dropdown, Toast.
7. **Write `src/app/layout.tsx`, `providers.tsx`, `globals.css`, `tailwind.config.ts`, `lib/utils.ts`, `lib/env.ts`.**
8. **Create one example feature page** under `src/app/(app)/{{feature}}/page.tsx` demonstrating: server fetch + Suspense, a form with rhf+zod, a list with TanStack Query mutation.
9. **Set up Vitest + RTL** (one component test) and **Playwright** (one E2E test).
10. **Write `Dockerfile`** with `output: 'standalone'` if `deployment_target=self-hosted`.
11. **Run `pnpm dev`** — verify the home page renders.
12. **Run `pnpm lint && pnpm type-check && pnpm test`** — clean.

---

## Companion deep-dive files

- [`01-stack-and-libraries.md`](./01-stack-and-libraries.md) — full library evaluation (read once, refer back)
- [`02-design-system-spec.md`](./02-design-system-spec.md) — full design system spec (1700+ lines)
- [`03-animations-and-motion.md`](./03-animations-and-motion.md) — Framer Motion patterns, route transitions, scroll
- [`04-mobile-responsive.md`](./04-mobile-responsive.md) — mobile-first responsive strategy
- [`05-forms-and-state.md`](./05-forms-and-state.md) — react-hook-form + zod, TanStack Query patterns
- [`06-testing-with-chrome-devtools-mcp.md`](./06-testing-with-chrome-devtools-mcp.md) — agent-driven E2E via MCP
