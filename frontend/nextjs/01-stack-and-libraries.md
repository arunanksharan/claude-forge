# Next.js Stack & Library Evaluation

> **Adapted from a production deployment of a multi-app monorepo (3D avatar chatbot + admin dashboard + ingestion UI). Library evaluations and rejections are real, run against shipping code.**
>
> Use this as your opinionated default. Override per project as needed — the rejected-library tables tell you when *not* to deviate.

## Production-Grade UI/UX for React / Next.js Applications

> Evaluated against: Linear, Vercel, Raycast quality bar.
> Compatible with: React 18 (Vite) + React 19 (Next.js 15/16), Tailwind CSS 3/4. 3D-specific picks (Three.js, R3F, VRM) are conditional — skip if you're not building 3D.

---

## Apps Covered

| App | Framework | Purpose |
|-----|-----------|---------|
| `frontend-app` | React 18 + Vite | Avatar chatbot (3D VRM + voice + SSE chat) |
| `admin-app` | Next.js 15 + React 19 | Dashboard (users, avatars, conversations) |
| `memory-service` | — | Knowledge graph & memory management |
| `ingestion-ui` | Next.js 16 + React 19 | Data ingestion from multiple sources |

---

## 1. FINAL RECOMMENDED STACK

### Shared Core (all apps)

| Category | Library | Size (gzip) | Why |
|----------|---------|-------------|-----|
| **Component System** | **shadcn/ui** (Radix + CVA + Tailwind) | ~0 (source code) | You own the code. Used by Linear, Vercel, Cal.com, Dub.co. Perfect Tailwind integration. |
| **Utility Classes** | `clsx` + `tailwind-merge` + `class-variance-authority` | ~3KB | Standard CVA pattern for variant-based styling |
| **Icons** | **`lucide-react`** | ~0 (tree-shaken) | 1500+ icons, consistent 24x24 stroke design, shadcn/ui default |
| **State (client)** | `zustand` | ~2KB | Already in use, minimal API, no provider wrappers |
| **State (server)** | `@tanstack/react-query` | ~13KB | Already in use, handles caching/refetch |
| **Forms** | `react-hook-form` + `zod` + `@hookform/resolvers` | ~22KB | Uncontrolled (minimal re-renders), Zod schemas shared with API |
| **Dates** | `date-fns` | ~3-8KB | Already in use, tree-shakeable, immutable |
| **Toast** | **`sonner`** | ~5KB | Best DX. `toast('Done')`. Created by Vercel design engineer |
| **Animation (DOM)** | **`framer-motion`** | ~33KB | Declarative React animations, AnimatePresence, layout animations |
| **Typography** | **Geist** (Sans + Mono) | ~100KB fonts | Vercel's font. Designed for UI/code. Variable weight. |
| **Design Tokens** | CSS Custom Properties + Tailwind theme | 0KB | Runtime theme switching, no JS cost |
| **Markdown Rendering** | `react-markdown` + `remark-gfm` + `@tailwindcss/typography` | ~12KB | For chat message rendering (LLM output is Markdown) |

### Frontend-Specific (frontend-app)

| Category | Library | Size (gzip) | Why |
|----------|---------|-------------|-----|
| **3D Engine** | `three` + `@react-three/fiber` + `@react-three/drei` | ~150KB | Already in use, R3F reconciler |
| **VRM Avatar** | `@pixiv/three-vrm` | ~50KB | Already in use, VRM expression/bone system |
| **Post-processing** | `@react-three/postprocessing` | ~30KB | JSX API for bloom, depth-of-field (replaces raw `postprocessing`) |
| **Lip Sync** | `wawa-lipsync` | ~5KB | Already in use |
| **Voice** | `livekit-client` | already present | WebRTC voice |
| **Auth** | `@react-oauth/google` | already present | Google OAuth |

### Admin-Specific (admin-app)

| Category | Library | Size (gzip) | Why |
|----------|---------|-------------|-----|
| **Tables** | `@tanstack/react-table` + `@tanstack/react-virtual` | ~15KB | Headless, Tailwind-styled, virtualized rows |
| **Charts** | **Recharts** (via shadcn charts) | ~45KB | Tailwind-compatible, dark mode, Vercel uses it |
| **DnD** | `dnd-kit` | ~13KB | Headless, accessible, keyboard support |
| **Rich Text** | `tiptap` (if editing needed) | ~50KB | ProseMirror-based, used by Linear, GitLab |

### Omnichannel-Specific (ingestion-ui)

| Category | Library | Size (gzip) | Why |
|----------|---------|-------------|-----|
| **Graph Viz** | `reagraph` OR `@xyflow/react` | varies | WebGL graph rendering / editable node flows |
| **Scroll Animation** | GSAP + ScrollTrigger (landing page only) | ~25KB | Timeline control for marketing sequences |
| **3D** | `three` + `@react-three/fiber` + `@react-three/drei` | already present | Shared with frontend |

---

## 2. EVALUATION OF YOUR RECOMMENDATIONS (nextjs.txt)

### KEEP (with notes)

| Library | Verdict | Notes |
|---------|---------|-------|
| `@react-three/fiber` + `@react-three/drei` + `three` | **KEEP** | Core 3D stack. No alternative for VRM. |
| `class-variance-authority` + `clsx` + `tailwind-merge` | **KEEP** | Standard shadcn/ui utility pattern. |
| `framer-motion` / `motion` | **KEEP** | Best React animation lib. Note: `framer-motion` and `motion` are the SAME library (v12+ rebrand). Only install one. |
| `lucide-react` | **KEEP** | Primary icon set. |
| `zustand` | **KEEP** | Already standardized. |
| `@radix-ui/react-slot` | **KEEP** | Part of shadcn/ui's `asChild` pattern. |
| `tailwindcss` + `@tailwindcss/postcss` | **KEEP** | Foundation. |
| `geist` | **KEEP** | Adopt across all apps. Excellent for AI/tech products. |
| `next` | **KEEP** | For admin + omnichannel (not frontend which uses Vite). |
| `react` + `react-dom` | **KEEP** | Obviously. |

### REMOVE

| Library | Verdict | Reason | Savings |
|---------|---------|--------|---------|
| `antd` | **REMOVE** | CSS-in-JS runtime (emotion) conflicts with Tailwind. 200-300KB. Your product will look like every Chinese enterprise app. | ~250KB |
| `antd-style` | **REMOVE** | Only exists to bridge antd to CSS-in-JS. Unnecessary without antd. | ~30KB |
| `@lobehub/ui` | **REMOVE** | Depends on antd under the hood. Not production-grade for Tailwind-first stack. Small team, frequent breaking changes. | ~50KB |
| `@lobehub/icons` | **REMOVE** | Tied to lobehub ecosystem. Use lucide-react instead. | ~10KB |
| `ogl` | **REMOVE IMMEDIATELY** | **Completely separate WebGL framework from Three.js.** Cannot share a canvas. You'd be shipping TWO WebGL engines (~180KB combined). Everything OGL does, Three.js + R3F does better. | ~30KB |
| `postprocessing` (raw) | **REPLACE** | Use `@react-three/postprocessing` instead — JSX API, automatic lifecycle management. | ~0 (replaced) |
| `lenis` | **REMOVE** | Hijacks native scroll. Breaks ctrl+F, anchor links, screen readers, scroll-snap, and Three.js canvas scroll. 12KB for a worse UX. Use native CSS `scroll-behavior: smooth`. | ~12KB |
| `rough-notation` | **REMOVE** | Niche hand-drawn annotation effect. Uses its own animation system (not Framer Motion). Only useful for one specific marketing design. | ~3.5KB |
| `react-icons` | **REMOVE** | Barrel-file re-export problem — imports entire icon set. 25+ inconsistent icon sets mixed together. Use lucide-react. | variable |

**Total estimated savings from removals: ~420KB+ gzipped**

### CONDITIONAL

| Library | Verdict | Condition |
|---------|---------|-----------|
| `gsap` + `@gsap/react` | **KEEP IF** you have scroll-triggered timeline sequences on landing/marketing pages. Otherwise Framer Motion's `whileInView` + `useScroll` covers 90% of needs. Check GSAP license for SaaS use. |

---

## 3. LIBRARY-BY-LIBRARY DEEP EVALUATION

### 3.1 Component Libraries

| Library | Score | Pros | Cons |
|---------|-------|------|------|
| **shadcn/ui** | **10/10** | Own the code, Tailwind-native, Radix accessibility, zero runtime CSS-in-JS, 85k+ stars | Not a package (copy-paste), requires initial setup |
| Mantine v7 | 7/10 | Batteries-included, great for admin | CSS modules (not Tailwind), coupling |
| @lobehub/ui | 4/10 | AI-specific components | antd dependency, CSS-in-JS, small team |
| Ant Design v6 | 5/10 | Comprehensive | CSS-in-JS (200-300KB), recognizable "antd look", bad Tailwind story |
| Chakra UI v3 | 5/10 | Good API | Panda CSS conflicts with Tailwind, ecosystem broken by v2→v3 |
| NextUI/HeroUI | 6/10 | Beautiful defaults | Thin coverage, Framer Motion dependency for everything |
| Radix Themes | 7/10 | Radix quality | Less flexible than shadcn/ui, Radix's tokens not yours |

**Winner: shadcn/ui.** No contest for Tailwind-first multi-app design systems.

### 3.2 Animation

| Library | Score | Best For | Three.js Compat |
|---------|-------|----------|-----------------|
| **Framer Motion** | **9/10** | React UI animations, layout, exit | No conflict (separate RAF) |
| GSAP + ScrollTrigger | 8/10 | Scroll timelines, sequencing | No conflict (use for DOM only) |
| React Spring | 5/10 | Physics-based | Fine but verbose, declining momentum |
| Motion One | 6/10 | Lightweight imperative | Loses AnimatePresence, layout animations |
| auto-animate | 4/10 | Quick list transitions | Too limited for production |

**Rule: Framer Motion for UI. `useFrame` for 3D. Never mix GSAP with Three.js objects.**

### 3.3 Icons

| Library | Score | Count | Tree-shake | Design Consistency |
|---------|-------|-------|------------|-------------------|
| **lucide-react** | **9/10** | 1500+ | Perfect | Excellent (24x24 stroke) |
| @phosphor-icons/react | 8/10 | 9000+ | Good | Excellent (6 weights) |
| react-icons | 4/10 | 40k+ | Poor (barrel imports) | Terrible (25+ mixed sets) |
| @tabler/icons-react | 7/10 | 5400+ | Good | Good |
| heroicons | 6/10 | ~300 | Perfect | Good but limited |

**Winner: lucide-react primary. Keep @phosphor-icons/react as secondary if you need specific icons not in Lucide.**

### 3.4 Charts (Admin Dashboard)

| Library | Score | Bundle | Tailwind Compat | Dark Mode |
|---------|-------|--------|-----------------|-----------|
| **Recharts** (shadcn charts) | **9/10** | ~45KB | Via CSS vars | Via CSS vars |
| Tremor | 8/10 | ~60KB | Native | Native |
| nivo | 7/10 | ~80KB+ | Needs work | Theme prop |
| visx | 6/10 | varies | Manual | Manual |
| Chart.js | 5/10 | ~40KB | Canvas (hard) | Theme prop |

**Winner: Recharts via shadcn/ui charts wrapper.** Pre-styled with your design tokens.

### 3.5 Tables

| Library | Score | Bundle | Headless | Features |
|---------|-------|--------|----------|----------|
| **TanStack Table v8** | **9/10** | ~15KB | Yes | Sort, filter, paginate, virtualize, pin |
| AG Grid | 8/10 | ~200KB | No | Excel-level (overkill for most) |
| Mantine DataTable | 6/10 | varies | No | Couples to Mantine styling |

### 3.6 Forms

| Library | Score | Re-renders | Validation |
|---------|-------|------------|------------|
| **React Hook Form + Zod** | **9/10** | Minimal (uncontrolled) | Zod schemas sharable with API |
| TanStack Form | 7/10 | Minimal | Type-safe-first, smaller ecosystem |
| Formik | 3/10 | Every keystroke (controlled) | Dead project (last update 2022) |

### 3.7 Toast/Notifications

| Library | Score | DX | Bundle |
|---------|-------|-----|--------|
| **sonner** | **9/10** | `toast('done')` | ~5KB |
| react-hot-toast | 7/10 | Similar | ~5KB |
| Radix Toast | 5/10 | Build everything yourself | ~2KB |

### 3.8 Rich Text / Markdown

| Library | Score | Best For |
|---------|-------|----------|
| **react-markdown** | **9/10** | Rendering LLM output (read-only) |
| **TipTap** | **8/10** | Rich text editing (admin) |
| Plate | 5/10 | Slate.js instability |
| MDXEditor | 6/10 | MDX-specific, too opinionated |

### 3.9 Drag and Drop

| Library | Score | Accessibility | Flexibility |
|---------|-------|---------------|-------------|
| **dnd-kit** | **9/10** | WCAG compliant | Sortable, grid, tree, kanban |
| @hello-pangea/dnd | 6/10 | Good | 1D lists only |
| pragmatic-drag-and-drop | 7/10 | Manual | Framework-agnostic (more boilerplate) |

### 3.10 Smooth Scrolling

| Option | Score | Recommendation |
|--------|-------|----------------|
| **Native CSS** | **10/10** | `scroll-behavior: smooth` + `scroll-snap` |
| Framer Motion `useScroll` | 9/10 | For scroll-linked animations |
| Lenis | 3/10 | Breaks native scroll, accessibility, Three.js |
| Locomotive Scroll | 2/10 | Same problems, heavier |

### 3.11 PostProcessing/WebGL

| Option | Score | Recommendation |
|--------|-------|----------------|
| **@react-three/postprocessing** | **9/10** | JSX API, lifecycle management, works with R3F |
| Raw `postprocessing` | 6/10 | Manual setup, no JSX |
| OGL | **0/10** | COMPLETELY SEPARATE ENGINE. Remove immediately. |

---

## 4. DESIGN TOKEN SYSTEM

### 4.1 Architecture

```
@example/design-system/
├── src/
│   ├── styles/globals.css       ← CSS custom properties (source of truth)
│   ├── tokens/motion.ts         ← Framer Motion variants & easing
│   ├── tokens/index.ts          ← Re-exports for JS consumers
│   ├── primitives/              ← Radix wrappers (Dialog, Dropdown, etc.)
│   ├── atoms/                   ← Button, Input, Badge, Avatar, Skeleton
│   ├── molecules/               ← ChatBubble, StatCard, SearchBar, FormField
│   ├── organisms/               ← ChatPanel, DataTable, Sidebar, Header
│   ├── templates/               ← ChatLayout, DashboardLayout
│   └── hooks/                   ← useTheme, useMediaQuery, useReducedMotion
├── tailwind.config.ts           ← Tailwind preset consuming CSS vars
└── package.json
```

### 4.2 Color Philosophy

- **Primary Violet** (#8b5cf6): Trust, intelligence, digital-native — Linear, Figma, Notion use this hue
- **Secondary Amber** (#f59e0b): Warmth, companion energy — counterbalances cold tech feel
- **Accent Cyan** (#06b6d4): Reserved for live/streaming/voice states
- **Warm Neutrals**: Not pure gray — HSL 258 hue at 4% saturation. Prevents sterile feel.
- **Dark mode first**: `:root` = dark. `.light` class = light. AI products live in dark mode.

### 4.3 Key Semantic Tokens

```css
:root {
  /* Surfaces (5-layer elevation) */
  --color-surface-base:    #0d0d0a;   /* page bg */
  --color-surface-raised:  #1a1a16;   /* cards */
  --color-surface-overlay: #26261f;   /* modals */
  --color-surface-sunken:  #141411;   /* inputs */
  --color-surface-glass:   rgba(26, 26, 22, 0.72);

  /* Text hierarchy */
  --color-text-primary:    #f4f4f2;
  --color-text-secondary:  #a8a8a3;
  --color-text-tertiary:   #71716c;

  /* Voice states (ExampleChat-specific) */
  --color-voice-active:    #22d3ee;
  --color-voice-listening: #06b6d4;
  --color-voice-processing:#a78bfa;

  /* 3D Scene lighting (consumed by Three.js) */
  --scene-ambient-intensity: 0.4;
  --scene-key-color:         #8b5cf6;
  --scene-rim-color:         #06b6d4;
}
```

### 4.4 Animation Tokens

```typescript
// Motion principles:
// 1. Meaning over decoration — every animation communicates state
// 2. Speed implies importance — fast=micro (100ms), normal=content (200ms), slow=navigation (350ms)
// 3. 3D and UI are separate layers — Three.js RAF ≠ Framer Motion RAF. Communicate via Zustand.

export const duration = { instant: 0, fast: 0.1, normal: 0.2, slow: 0.35, glacial: 0.7 }
export const ease = {
  out:    [0, 0, 0.2, 1],        // default for entries
  in:     [0.4, 0, 1, 1],        // for exits
  spring: [0.34, 1.56, 0.64, 1], // for modals, emphasis
}
```

### 4.5 Shadows

```
glow-sm:    0px 0px 8px rgba(139, 92, 246, 0.35)     ← brand glow on CTAs
glow-md:    0px 0px 16px rgba(139, 92, 246, 0.40)    ← hover state
glow-voice: 0px 0px 24px rgba(6, 182, 212, 0.50)     ← active voice call
```

### 4.6 Responsive Strategy

```
xs:  360px   ← small phones
sm:  480px   ← large phones
md:  768px   ← tablets
lg:  1024px  ← laptops
xl:  1280px  ← desktops
2xl: 1440px  ← wide
3xl: 1920px  ← ultra-wide (admin dashboards)
```

- **Chatbot UI**: Mobile-first (xs → up)
- **Admin Dashboard**: Desktop-optimized (lg → down)
- Touch targets: minimum 44px (`h-11`, `min-h-touch`)

---

## 5. MIGRATION CHECKLIST

### Immediate (omnichannel cleanup — saves ~420KB)

- [ ] Remove `ogl` — two WebGL engines is an architectural mistake
- [ ] Remove `antd` + `antd-style` + `@lobehub/ui` + `@lobehub/icons`
- [ ] Remove duplicate `framer-motion` (keep `motion`)
- [ ] Remove `lenis`
- [ ] Remove `rough-notation`
- [ ] Remove `react-icons` (use lucide-react)

### Soon (frontend cleanup)

- [ ] Remove `react-icons` (consolidate to lucide-react)
- [ ] Replace `@radix-ui/react-toast` with `sonner`
- [ ] Add `react-markdown` + `remark-gfm` + `@tailwindcss/typography` for chat rendering
- [ ] Add `geist` font

### Shared Design System (when ready)

- [ ] Extract CSS custom properties to `@example/design-system`
- [ ] Extract Tailwind preset (shared colors, spacing, typography)
- [ ] Extract shadcn/ui components into shared package
- [ ] Standardize component patterns (Button, Input, Badge, etc.)

---

## 6. COMPLETE DEPENDENCY LIST (per app)

### frontend-app (React 18 + Vite)

```
# Core
react, react-dom, react-router-dom, typescript, vite

# UI System
@radix-ui/react-dialog, @radix-ui/react-dropdown-menu, @radix-ui/react-scroll-area,
@radix-ui/react-slot, @radix-ui/react-tabs, @radix-ui/react-tooltip
class-variance-authority, clsx, tailwind-merge, tailwindcss, @tailwindcss/typography

# State & Data
zustand, @tanstack/react-query, react-hook-form, zod, @hookform/resolvers

# Animation
framer-motion (or motion)

# 3D & Avatar
three, @react-three/fiber, @react-three/drei, @react-three/postprocessing
@pixiv/three-vrm, wawa-lipsync

# Chat & Content
react-markdown, remark-gfm

# Icons & Typography
lucide-react, geist

# Utilities
date-fns, sonner, dompurify, i18next, react-i18next

# Auth & Comms
@react-oauth/google, livekit-client, socket.io-client

# Observability (keep as-is)
@opentelemetry/* packages
```

### admin-app (Next.js 15 + React 19)

```
# Core
next, react, react-dom, typescript

# UI System (shadcn/ui pattern — already in place)
@radix-ui/* primitives, class-variance-authority, clsx, tailwind-merge, tailwindcss

# State & Data
zustand, @tanstack/react-query, react-hook-form, zod, @hookform/resolvers

# Animation
framer-motion

# Tables & Charts
@tanstack/react-table, @tanstack/react-virtual, recharts

# Icons & Typography
lucide-react, geist

# Utilities
date-fns, sonner, next-themes

# Add when needed
dnd-kit, tiptap
```

### ingestion-ui (Next.js 16 + React 19) — AFTER CLEANUP

```
# Core
next, react, react-dom, typescript

# UI System
@radix-ui/* primitives, class-variance-authority, clsx, tailwind-merge, tailwindcss

# State & Data
zustand, @tanstack/react-query, react-hook-form, zod, @hookform/resolvers

# Animation
motion (framer-motion v12+)

# 3D (only if needed for VRM preview)
three, @react-three/fiber, @react-three/drei

# Graph Visualization
reagraph (or @xyflow/react for editable flows)

# Scroll (landing page only, conditional)
gsap, @gsap/react

# Icons & Typography
lucide-react, geist

# Utilities
date-fns, sonner
```

---

## 7. WHAT NOT TO USE (evaluated & rejected)

| Library | Category | Why Not |
|---------|----------|---------|
| Chakra UI v3 | Components | Panda CSS conflicts with Tailwind |
| NextUI/HeroUI | Components | Thin coverage, Framer Motion dep for all components |
| Mantine | Components | CSS modules, not Tailwind-native |
| Formik | Forms | Dead project, controlled components, slow |
| dayjs | Dates | Not tree-shakeable |
| Temporal API | Dates | Still Stage 3, 50KB polyfill |
| Locomotive Scroll | Scroll | Worse than Lenis (which is already bad) |
| Chart.js | Charts | Canvas-based, hard to style with Tailwind |
| AG Grid | Tables | 200KB, overkill for admin dashboards |
| Plate | Rich Text | Slate.js instability |
| react-beautiful-dnd | DnD | Abandoned by Atlassian |
| Styled Components | Styling | Runtime CSS-in-JS, conflicts with Tailwind |
| Emotion | Styling | Runtime CSS-in-JS, used by antd (that's the problem) |
| Material UI | Components | Emotion-based, Google design language |

---

## 8. ACCESSIBILITY STANDARDS

- WCAG 2.1 AA minimum across all apps
- Focus management: `focus-ring` utility (2px solid violet, 2px offset)
- Chat: `role="log"` with `aria-live="polite"` for new messages
- Voice: announce state changes via `aria-live` ("Voice call started", "Listening...")
- Keyboard: all interactive elements focusable, escape closes modals
- Motion: respect `prefers-reduced-motion` via `useReducedMotion` hook
- Touch targets: minimum 44x44px (`min-h-touch min-w-touch`)
- Color contrast: 4.5:1 for text, 3:1 for large text and UI components

---

*Last evaluated: 2026-04-02*
*Stack designed for: React 18/19, Vite/Next.js, Tailwind CSS 3/4, Three.js r172*
