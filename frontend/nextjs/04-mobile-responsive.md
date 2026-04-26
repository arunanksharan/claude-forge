# Mobile-First & Responsive

> Tailwind-driven responsive strategy, touch targets, viewport tricks, mobile-only concerns.

## Strategy: mobile-first, always

Tailwind defaults to mobile-first: classes without a breakpoint apply at all sizes; breakpoint prefixes (`sm:`, `md:`, etc.) apply *upward*.

```tsx
<div className="text-base md:text-lg lg:text-xl">
```

Means: 16px on mobile, 18px on tablet+, 20px on desktop+.

**Rule:** design the mobile layout first, then add breakpoint classes for larger screens. Reverse engineering "desktop with mobile fallback" produces busy code and bugs at small sizes.

## Breakpoints

The design system spec defines:

```typescript
xs:  360px   ← small phones (custom)
sm:  480px   ← large phones (custom — Tailwind default is 640)
md:  768px   ← tablets
lg:  1024px  ← laptops
xl:  1280px  ← desktops
2xl: 1440px  ← wide
3xl: 1920px  ← ultra-wide
```

The custom `xs` and `sm` matter for chat / feed apps where 360px is real. Configure in `tailwind.config.ts`:

```typescript
theme: {
  screens: {
    xs: '360px',
    sm: '480px',
    md: '768px',
    lg: '1024px',
    xl: '1280px',
    '2xl': '1440px',
    '3xl': '1920px',
  },
}
```

## Viewport meta (Next.js)

In `app/layout.tsx` Next 13+ uses the `viewport` export:

```tsx
import type { Viewport } from 'next';

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,            // allow zoom — accessibility
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#0d0d0a' },
    { media: '(prefers-color-scheme: light)', color: '#ffffff' },
  ],
  // viewportFit: 'cover',     // for iOS notch — see below
};
```

**Don't set `userScalable: false` / `maximumScale: 1`** — it breaks accessibility for users who need to zoom.

## Touch targets (44×44 minimum)

WCAG and Apple HIG agree: **44×44 CSS pixels minimum** for touchable elements.

Add a token:

```typescript
// in tailwind.config.ts
spacing: {
  touch: '2.75rem',   // 44px at 16px base
}
```

```tsx
<button className="h-touch min-w-touch px-4">Submit</button>
```

For icon-only buttons, never go below 44×44 even if the icon is 20px:

```tsx
<button className="grid h-touch w-touch place-items-center">
  <Menu className="size-5" />
</button>
```

## Safe area (iOS notch / Android gestures)

iPhones with notches and Android devices with gesture bars need padding to avoid content being clipped or overlapping system UI.

Set `viewportFit: 'cover'` in `viewport`, then use CSS env variables:

```css
/* globals.css */
@layer utilities {
  .safe-top { padding-top: max(env(safe-area-inset-top), 0px); }
  .safe-bottom { padding-bottom: max(env(safe-area-inset-bottom), 0px); }
  .safe-x { padding-inline: max(env(safe-area-inset-left), env(safe-area-inset-right), 0px); }
}
```

Apply on full-bleed elements:

```tsx
<header className="fixed top-0 inset-x-0 safe-top safe-x bg-surface-overlay">
```

```tsx
<nav className="fixed bottom-0 inset-x-0 safe-bottom safe-x">
```

## Dynamic viewport units (mobile address bar)

`100vh` is broken on mobile — it's the *initial* viewport height, but mobile browsers shrink the viewport when the URL bar collapses, leaving you with a layout that doesn't fit.

Use the new dynamic units:

| Unit | Behavior |
|------|----------|
| `100dvh` | dynamic — recomputes as the viewport changes |
| `100svh` | small — when the URL bar is showing |
| `100lvh` | large — when the URL bar is hidden |

```tsx
<main className="min-h-[100dvh] flex flex-col">
```

Tailwind 4 has `min-h-dvh`, `h-dvh`. For Tailwind 3, use arbitrary values: `min-h-[100dvh]`.

## Container queries

Sometimes a component needs to respond to its **container** size, not the viewport. (Sidebar collapsed vs expanded, modal vs full-page.)

```tsx
<div className="@container">
  <div className="flex flex-col @md:flex-row">
```

The child becomes a row when its container is `>= 28rem` wide, regardless of viewport size. Useful for components that ship in many contexts.

Tailwind 4 has container queries built in. Tailwind 3 needs the `@tailwindcss/container-queries` plugin.

## Mobile-specific patterns

### Bottom sheet vs modal

On mobile, a centered modal feels foreign. Use a bottom sheet that slides up:

```tsx
import { Drawer } from 'vaul';   // pnpm add vaul

<Drawer.Root open={open} onOpenChange={setOpen}>
  <Drawer.Trigger>Open</Drawer.Trigger>
  <Drawer.Portal>
    <Drawer.Overlay className="fixed inset-0 bg-black/40" />
    <Drawer.Content className="fixed inset-x-0 bottom-0 rounded-t-2xl bg-surface-raised">
      <div className="mx-auto mt-3 h-1.5 w-12 rounded-full bg-text-tertiary" />
      <div className="p-4 safe-bottom">...</div>
    </Drawer.Content>
  </Drawer.Portal>
</Drawer.Root>
```

`vaul` is a bottom sheet that handles drag-to-dismiss, scroll, snap points. Made by the shadcn maintainer.

For desktop, use a centered Radix Dialog. Conditionally render based on `useMediaQuery`:

```tsx
const isMobile = useMediaQuery('(max-width: 768px)');
return isMobile ? <BottomSheet /> : <Dialog />;
```

### Sticky bottom CTA

```tsx
<div className="fixed inset-x-0 bottom-0 safe-bottom bg-surface-overlay/80 backdrop-blur p-4 border-t border-text-tertiary/20">
  <button className="w-full h-touch bg-brand text-brand-fg rounded-lg">
    Continue
  </button>
</div>
```

### Avoid hover-only interactions

`@media (hover: hover)` is your friend. Hide hover states on touch devices:

```tsx
<button className="bg-surface-raised hover:bg-surface-overlay [@media(hover:none)]:hover:bg-surface-raised">
```

Or just rely on `active:` for touch feedback:

```tsx
<button className="bg-brand active:bg-brand-700 transition-colors">
```

### Scroll lock on modal

When a sheet is open, prevent the page behind from scrolling:

```typescript
useEffect(() => {
  if (open) document.body.style.overflow = 'hidden';
  return () => { document.body.style.overflow = ''; };
}, [open]);
```

Radix Dialog and vaul handle this automatically.

### Input zoom on iOS

iOS zooms in when you focus an input with `font-size < 16px`. Avoid:

```css
input, select, textarea { font-size: 16px; }
```

Or in Tailwind: ensure inputs are `text-base` (16px) or larger.

## Tables on mobile

Tables don't fit. Two options:

1. **Card mode**: at small sizes, render each row as a card

```tsx
<div className="md:hidden space-y-2">
  {items.map((i) => <Card key={i.id} {...i} />)}
</div>
<table className="hidden md:table">
  ...
</table>
```

2. **Horizontal scroll**: keep the table, scroll inside its container

```tsx
<div className="overflow-x-auto">
  <table className="min-w-[600px]">...</table>
</div>
```

Card mode is usually the better UX. Horizontal scroll is fine for data-dense tools used by power users.

## Images

Always use `next/image`:

```tsx
import Image from 'next/image';

<Image
  src="/hero.jpg"
  alt="..."
  width={1200}
  height={800}
  sizes="(max-width: 768px) 100vw, (max-width: 1280px) 50vw, 33vw"
  priority      // for above-the-fold; otherwise lazy-loads
/>
```

The `sizes` attribute tells the browser which image variant to download per breakpoint. Without it, the browser downloads the largest.

## Detecting orientation

```typescript
const isLandscape = useMediaQuery('(orientation: landscape)');
```

Useful for video players, image editors, anything that wants a different layout in landscape.

## `useMediaQuery` hook

```tsx
// src/hooks/use-media-query.ts
'use client';

import { useEffect, useState } from 'react';

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const mql = window.matchMedia(query);
    const handler = (e: MediaQueryListEvent) => setMatches(e.matches);
    setMatches(mql.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, [query]);

  return matches;
}
```

Returns `false` on first render (SSR safe), then updates after hydration. For SSR-aware logic, prefer CSS over JS where possible.

## PWA basics (if needed)

If the app needs to be installable / offline:

```bash
pnpm add @ducanh2912/next-pwa
```

Or roll your own with `next-pwa` workbox patterns. Add a manifest:

```json
// public/manifest.json
{
  "name": "{{project-name}}",
  "short_name": "{{short}}",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0d0d0a",
  "theme_color": "#8b5cf6",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

Reference in layout:

```tsx
export const metadata: Metadata = {
  manifest: '/manifest.json',
};
```

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `100vh` jumps when address bar shows/hides | Use `100dvh` |
| Touch target too small | Audit with browser dev tools "device toolbar"; min 44×44 |
| Hover state stuck on touch device | `@media (hover: hover)` |
| Form inputs zoom on focus (iOS) | `font-size: 16px` minimum |
| Bottom CTA covered by gesture bar | `safe-bottom` padding |
| Modal scroll behind sheet on mobile | Use Radix Dialog or vaul; they handle it |
| Sidebar on mobile pushes content | Use a sheet/drawer pattern, not a sidebar |
| `100%` width input overflow on iOS | `box-sizing: border-box` (Tailwind sets this globally — fine) |
| Layout shift from late-loading fonts | `next/font` handles this with `display: 'swap'` and font preloading |
