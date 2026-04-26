---
name: scaffold-nextjs
description: Use when the user wants to scaffold a new Next.js 15+ project with React 19, the claudeforge locked stack (shadcn/ui, framer-motion, TanStack Query, Zustand, react-hook-form + zod, lucide-react, sonner, Geist), App Router, Tailwind 4, design system tokens. Triggers on "new nextjs project", "scaffold next.js", "next 15 app", "next.js with shadcn".
---

# Scaffold Next.js Project (claudeforge)

Follow the master prompt at `frontend/nextjs/PROMPT.md`. Steps:

1. **Confirm parameters**: `project_name`, `project_slug` (kebab-case), app type (web/admin/landing/chat), include 3D/auth, brand primary color, deployment target (vercel vs self-hosted).
2. **Read foundational docs**:
   - `frontend/nextjs/PROMPT.md` — master prompt with directory tree, deps, key files
   - `frontend/nextjs/01-stack-and-libraries.md` — locked library list with rationale
   - `frontend/nextjs/02-design-system-spec.md` — token system if creating a design system
3. **Read deep-dives** as needed:
   - `03-animations-and-motion.md` — Framer Motion patterns
   - `04-mobile-responsive.md` — mobile-first, dvh, safe-area, touch targets
   - `05-forms-and-state.md` — rhf+zod, TanStack Query, Zustand, URL state
4. **Generate**: `pnpm create next-app` with TS+Tailwind+ESLint+src-dir+App Router, replace deps with locked stack, init shadcn/ui, install initial UI components (button/input/label/dialog/dropdown/toast), write `layout.tsx`, `providers.tsx`, `globals.css` with token CSS vars, `tailwind.config.ts` with semantic tokens, `lib/utils.ts` (cn), `lib/env.ts` (zod), one example feature page demonstrating Server Component + form + TanStack Query mutation.
5. **Verify**: `pnpm dev` works, `pnpm lint && pnpm type-check && pnpm test` clean.
6. **If deployment_target=self-hosted**: also create Dockerfile with `output: 'standalone'` (see `deployment/per-framework/deploy-nextjs.md`).

Do NOT install antd, Mantine, react-icons, formik, lenis, ogl, or any rejected library from `01-stack-and-libraries.md` section 7.
