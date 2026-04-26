# Animations & Motion in Next.js

> Framer Motion patterns for React 19 + Next.js App Router. When to use what, and what to avoid.

## Decision: animation library

| Lib | Verdict |
|-----|---------|
| **framer-motion** (now `motion`) | Pick this. Best React API, layout animations, AnimatePresence, gesture support. |
| **GSAP + ScrollTrigger** | Use *only* for marketing landing pages with complex scroll sequences. License check for SaaS. |
| **React Spring** | Declining momentum. Skip. |
| **Motion One** | Imperative; loses the React API benefits. |
| **auto-animate** | Quick demos only. |
| **CSS transitions / animations** | Yes — for simple state transitions, prefer CSS. Faster, no JS. |

`framer-motion` and `motion` are the same library. Install one (`framer-motion` is still the more recognized name).

## Motion principles (from `02-design-system-spec.md`)

1. **Meaning over decoration** — every animation communicates state change
2. **Speed implies importance** — fast (100ms) = micro, normal (200ms) = content, slow (350ms) = navigation
3. **3D and UI are separate layers** — Three.js RAF ≠ Framer Motion RAF
4. **Respect `prefers-reduced-motion`**

## Duration + easing tokens

```typescript
// src/lib/motion.ts
export const duration = {
  instant: 0,
  fast: 0.1,
  normal: 0.2,
  slow: 0.35,
  glacial: 0.7,
} as const;

export const ease = {
  out:    [0, 0, 0.2, 1] as const,         // entries (default)
  in:     [0.4, 0, 1, 1] as const,         // exits
  spring: [0.34, 1.56, 0.64, 1] as const,  // emphasis (modals, success states)
} as const;

export const fadeIn = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: { duration: duration.normal, ease: ease.out } },
  exit: { opacity: 0, transition: { duration: duration.fast, ease: ease.in } },
};

export const slideUp = {
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: { duration: duration.normal, ease: ease.out } },
  exit: { opacity: 0, y: -16, transition: { duration: duration.fast, ease: ease.in } },
};
```

Reuse the variants — don't reinvent timing per component.

## When CSS beats JS

For simple state transitions (hover, focus, active), use Tailwind's `transition-*` utilities:

```tsx
<button className="transition-colors duration-200 ease-out hover:bg-brand">
  Click
</button>
```

CSS runs on the compositor thread, no React re-render, ~zero overhead. Reach for Framer Motion when you need:

- Enter/exit animations (CSS can't see "removed from DOM")
- Spring physics
- Layout animations (FLIP)
- Gestures (drag, swipe)
- Coordinated sequences

## AnimatePresence for enter/exit

```tsx
'use client';

import { AnimatePresence, motion } from 'framer-motion';
import { fadeIn } from '@/lib/motion';

export function Modal({ open, children }: { open: boolean; children: React.ReactNode }) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          {...fadeIn}
          className="fixed inset-0 z-50 grid place-items-center bg-black/40"
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
```

Critical: the conditional must be **inside** `<AnimatePresence>` — `{open && <motion.div />}`. If you put `<motion.div />` always rendered with conditional content, exit animations don't fire.

## Layout animations

```tsx
<motion.div layout>
  {items.map((i) => (
    <motion.div key={i.id} layout>
      {i.label}
    </motion.div>
  ))}
</motion.div>
```

When the parent reflows or items reorder, Framer Motion FLIPs them smoothly. Use sparingly — easy to abuse.

## Page transitions in App Router

Next.js App Router doesn't expose a direct transition hook. Use `template.tsx`:

```tsx
// src/app/template.tsx
'use client';

import { motion } from 'framer-motion';

export default function Template({ children }: { children: React.ReactNode }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2, ease: [0, 0, 0.2, 1] }}
    >
      {children}
    </motion.div>
  );
}
```

`template.tsx` re-mounts on every route change (unlike `layout.tsx`), so the animation fires.

For **shared element transitions** between routes, `next-view-transitions` wraps the View Transitions API:

```bash
pnpm add next-view-transitions
```

```tsx
// app/layout.tsx
import { ViewTransitions } from 'next-view-transitions';

export default function RootLayout({ children }) {
  return (
    <ViewTransitions>
      <html><body>{children}</body></html>
    </ViewTransitions>
  );
}
```

```tsx
// in a card that should morph into a detail page
<div style={{ viewTransitionName: `card-${id}` }}>...</div>
```

The browser handles the cross-route transition. Works on Chromium; falls back to no transition on Firefox.

## Scroll-linked animations

```tsx
'use client';

import { useScroll, useTransform, motion } from 'framer-motion';

export function ParallaxHero() {
  const { scrollYProgress } = useScroll();
  const y = useTransform(scrollYProgress, [0, 1], [0, -100]);

  return <motion.div style={{ y }}>...</motion.div>;
}
```

For **viewport-triggered** animations (animate when scrolled into view):

```tsx
<motion.div
  initial={{ opacity: 0, y: 24 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true, margin: '-50px' }}
  transition={{ duration: 0.4 }}
>
  ...
</motion.div>
```

`viewport={{ once: true }}` fires only on first entry. `margin: '-50px'` triggers when 50px past the viewport edge (avoids "fires immediately on load").

## Stagger children

```tsx
const container = {
  initial: {},
  animate: { transition: { staggerChildren: 0.05 } },
};

const item = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.2 } },
};

<motion.ul variants={container} initial="initial" animate="animate">
  {items.map((i) => (
    <motion.li key={i.id} variants={item}>{i.label}</motion.li>
  ))}
</motion.ul>
```

The parent's `staggerChildren` cascades the start time of each child.

## Drag + gestures

```tsx
<motion.div
  drag
  dragConstraints={{ left: -100, right: 100, top: 0, bottom: 0 }}
  dragElastic={0.2}
  whileDrag={{ scale: 1.05 }}
>
  ...
</motion.div>
```

For swipe-to-dismiss:

```tsx
<motion.div
  drag="x"
  dragConstraints={{ left: 0, right: 0 }}
  onDragEnd={(_, info) => {
    if (Math.abs(info.offset.x) > 100) onDismiss();
  }}
>
```

## Reduced motion

```tsx
import { useReducedMotion } from 'framer-motion';

export function HeroAnimation() {
  const reduce = useReducedMotion();
  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
    >
      ...
    </motion.div>
  );
}
```

When `prefers-reduced-motion: reduce` is set:
- Disable parallax / heavy motion
- Keep simple opacity fades (these are usually fine)
- Provide instant state changes for important UX cues

## Performance

| Tip | Why |
|-----|-----|
| Animate `transform` and `opacity` only | Compositor-only properties; cheap |
| Avoid animating `width`, `height`, `top`, `left` | Layout-triggering; janky |
| Use `layoutId` (FLIP) instead of resizing | Smoother |
| `will-change: transform` only on actively animating elements | Otherwise wastes GPU memory |
| For lists, virtualize (`@tanstack/react-virtual`) | Animating 1000 items = jank |
| Don't animate inside loops or `useEffect` | Use Framer Motion variants — browser optimizes |

## Three.js coordination

If your page has both DOM Framer Motion **and** a Three.js canvas:

- Don't put 3D objects inside `motion.*` wrappers — they're HTML, three.js renders to canvas
- Communicate via Zustand: `motion.button onClick={() => setSceneState('active')}`
- The R3F scene reads the Zustand state with `useFrame` for per-frame interpolation
- Never animate Three.js objects with Framer Motion — use `useFrame` + lerp/spring math directly

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Exit animation doesn't play | Wrap with `<AnimatePresence>` and conditionally render the motion element |
| `layout` prop causes flickers | Set `layoutScroll` on the scrollable container; or use `layoutId` for shared element |
| Component flashes on initial mount | Set `initial={false}` to skip initial animation |
| Hydration mismatch with motion props | Make the parent `'use client'` |
| Animations feel laggy on mobile | Profile with React DevTools + Performance tab; ensure no layout-triggering |
| `whileInView` triggers immediately | Use negative `margin` on viewport |
| GSAP imports break SSR | Wrap GSAP usage in `useEffect` or `dynamic(import, { ssr: false })` |
| Framer Motion v12 breaking changes | The API is mostly the same; use the migration guide |
