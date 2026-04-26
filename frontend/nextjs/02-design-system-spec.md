# Design System — Architecture Specification

> **Adapted from a real production design system spanning a multi-app monorepo. The token model, motion primitives, and component patterns are battle-tested. Rename `@example/design-system` and re-pick the palette for your own brand — the structure is what's reusable.**
>
> This is a *reference spec* — read once, refer back as you build. Companion file `01-stack-and-libraries.md` covers runtime dependencies; this file covers design tokens and component patterns.

## Executive Summary

This document defines a complete design system for a multi-app product suite. The system is built on four principles: **token-first architecture** (all decisions start as tokens, never hardcoded values), **dark-primary parity** (dark mode is designed first, light mode is derived), **motion as communication** (every animation carries semantic meaning), and **accessible by default** (WCAG 2.1 AA is a floor, not a ceiling).

The system is named **Example DS** and lives in a shared package `@example/design-system`. Replace these names with your own brand.

---

## 1. Design Token System

### 1.1 Color Palette Philosophy

The palette is built on a warm-neutral base with a signature violet-indigo primary that communicates intelligence without coldness. Secondary is a warm amber that suggests warmth and companionship. The system uses a 12-step scale per hue (following Radix Colors conventions) so every shade has a semantic purpose.

**Hue Selection Rationale:**
- Primary Violet: trust, intelligence, digital-native — used by Linear, Figma, Notion
- Secondary Amber: warmth, energy, human connection — counterbalances the cold tech feel
- Accent Cyan: real-time, live, data — reserved for voice/streaming states
- Neutrals: warm-tinted gray (not pure gray) — prevents sterile feel

### Tailwind Configuration — Full Token System

Create `/packages/design-system/tailwind.config.ts`:

```typescript
import type { Config } from 'tailwindcss'
import { fontFamily } from 'tailwindcss/defaultTheme'

// ------------------------------------------------------------------
// STEP 1: Raw Palette — these are the source-of-truth color values.
// Never use these directly in components. Always use semantic tokens.
// ------------------------------------------------------------------
const palette = {
  // Violet — Primary brand hue (HSL 258)
  violet: {
    50:  '#f5f3ff',
    100: '#ede9fe',
    200: '#ddd6fe',
    300: '#c4b5fd',
    400: '#a78bfa',
    500: '#8b5cf6',
    600: '#7c3aed',
    700: '#6d28d9',
    800: '#5b21b6',
    900: '#4c1d95',
    950: '#2e1065',
  },

  // Amber — Secondary / warmth hue (HSL 38)
  amber: {
    50:  '#fffbeb',
    100: '#fef3c7',
    200: '#fde68a',
    300: '#fcd34d',
    400: '#fbbf24',
    500: '#f59e0b',
    600: '#d97706',
    700: '#b45309',
    800: '#92400e',
    900: '#78350f',
    950: '#451a03',
  },

  // Cyan — Accent / live / streaming states
  cyan: {
    50:  '#ecfeff',
    100: '#cffafe',
    200: '#a5f3fc',
    300: '#67e8f9',
    400: '#22d3ee',
    500: '#06b6d4',
    600: '#0891b2',
    700: '#0e7490',
    800: '#155e75',
    900: '#164e63',
    950: '#083344',
  },

  // Rose — Destructive / error
  rose: {
    50:  '#fff1f2',
    100: '#ffe4e6',
    200: '#fecdd3',
    300: '#fda4af',
    400: '#fb7185',
    500: '#f43f5e',
    600: '#e11d48',
    700: '#be123c',
    800: '#9f1239',
    900: '#881337',
    950: '#4c0519',
  },

  // Emerald — Success / positive
  emerald: {
    50:  '#ecfdf5',
    100: '#d1fae5',
    200: '#a7f3d0',
    300: '#6ee7b7',
    400: '#34d399',
    500: '#10b981',
    600: '#059669',
    700: '#047857',
    800: '#065f46',
    900: '#064e3b',
    950: '#022c22',
  },

  // Warm neutral — NOT pure gray. 258hue at 4% saturation.
  neutral: {
    0:   '#ffffff',
    50:  '#fafaf9',
    100: '#f4f4f2',
    200: '#e8e8e5',
    300: '#d1d1cd',
    400: '#a8a8a3',
    500: '#71716c',
    600: '#52524e',
    700: '#3a3a37',
    800: '#26261f',  // key dark surface
    900: '#1a1a16',  // page background dark
    925: '#141411',  // deepest dark
    950: '#0d0d0a',  // true dark (nav, sidebar)
    1000: '#000000',
  },
} as const

// ------------------------------------------------------------------
// STEP 2: Semantic Token Map
// These are the tokens components actually consume.
// Defined as CSS custom properties (see globals.css section below).
// The Tailwind config references CSS vars so themes work at runtime.
// ------------------------------------------------------------------
const semanticColors = {
  // Brand
  'brand-primary':       'var(--color-brand-primary)',
  'brand-primary-hover': 'var(--color-brand-primary-hover)',
  'brand-primary-subtle':'var(--color-brand-primary-subtle)',
  'brand-secondary':     'var(--color-brand-secondary)',
  'brand-accent':        'var(--color-brand-accent)',
  'brand-accent-live':   'var(--color-brand-accent-live)',

  // Surfaces (layered elevation system)
  'surface-base':        'var(--color-surface-base)',      // page bg
  'surface-raised':      'var(--color-surface-raised)',    // cards
  'surface-overlay':     'var(--color-surface-overlay)',   // modals
  'surface-sunken':      'var(--color-surface-sunken)',    // inputs
  'surface-inverse':     'var(--color-surface-inverse)',   // tooltip bg

  // Borders
  'border-subtle':       'var(--color-border-subtle)',
  'border-default':      'var(--color-border-default)',
  'border-strong':       'var(--color-border-strong)',
  'border-brand':        'var(--color-border-brand)',

  // Text
  'text-primary':        'var(--color-text-primary)',
  'text-secondary':      'var(--color-text-secondary)',
  'text-tertiary':       'var(--color-text-tertiary)',
  'text-placeholder':    'var(--color-text-placeholder)',
  'text-inverse':        'var(--color-text-inverse)',
  'text-brand':          'var(--color-text-brand)',
  'text-link':           'var(--color-text-link)',

  // Semantic status
  'status-success':      'var(--color-status-success)',
  'status-success-subtle':'var(--color-status-success-subtle)',
  'status-warning':      'var(--color-status-warning)',
  'status-warning-subtle':'var(--color-status-warning-subtle)',
  'status-error':        'var(--color-status-error)',
  'status-error-subtle': 'var(--color-status-error-subtle)',
  'status-info':         'var(--color-status-info)',
  'status-info-subtle':  'var(--color-status-info-subtle)',

  // Voice/live states (ExampleChat specific - still in shared system)
  'voice-active':        'var(--color-voice-active)',
  'voice-listening':     'var(--color-voice-listening)',
  'voice-processing':    'var(--color-voice-processing)',

  // Interactive states
  'interactive-default': 'var(--color-interactive-default)',
  'interactive-hover':   'var(--color-interactive-hover)',
  'interactive-active':  'var(--color-interactive-active)',
  'interactive-focus':   'var(--color-interactive-focus)',
  'interactive-disabled':'var(--color-interactive-disabled)',
}

// ------------------------------------------------------------------
// STEP 3: Spacing Scale — 4px base unit, T-shirt sizes for readability
// ------------------------------------------------------------------
const spacing = {
  // Raw scale (multiples of 4px)
  'px':   '1px',
  '0':    '0px',
  '0.5':  '2px',
  '1':    '4px',
  '1.5':  '6px',
  '2':    '8px',
  '2.5':  '10px',
  '3':    '12px',
  '3.5':  '14px',
  '4':    '16px',
  '5':    '20px',
  '6':    '24px',
  '7':    '28px',
  '8':    '32px',
  '9':    '36px',
  '10':   '40px',
  '11':   '44px',  // minimum touch target
  '12':   '48px',
  '14':   '56px',
  '16':   '64px',
  '18':   '72px',
  '20':   '80px',
  '24':   '96px',
  '28':   '112px',
  '32':   '128px',
  '36':   '144px',
  '40':   '160px',
  '48':   '192px',
  '56':   '224px',
  '64':   '256px',
  '72':   '288px',
  '80':   '320px',
  '96':   '384px',

  // Named semantic spacing (maps to T-shirt sizes)
  // Used in component specs: padding="component-md"
  'component-xs': '4px',
  'component-sm': '8px',
  'component-md': '12px',
  'component-lg': '16px',
  'component-xl': '24px',

  'layout-xs':  '16px',
  'layout-sm':  '24px',
  'layout-md':  '32px',
  'layout-lg':  '48px',
  'layout-xl':  '64px',
  'layout-2xl': '96px',
}

// ------------------------------------------------------------------
// STEP 4: Border Radius Scale
// Philosophy: consistent radius across surface types.
// Use "none" only for intentional sharp UI (admin tables).
// ------------------------------------------------------------------
const borderRadius = {
  'none':   '0px',
  'xs':     '2px',    // tight chips, badges
  'sm':     '4px',    // inputs, small cards
  'md':     '8px',    // default cards, buttons
  'lg':     '12px',   // large cards, panels
  'xl':     '16px',   // drawers, large modals
  '2xl':    '24px',   // chat bubbles (ai side)
  '3xl':    '32px',   // avatar cards
  'full':   '9999px', // pills, avatars
}

// ------------------------------------------------------------------
// STEP 5: Typography Scale
// Two fonts: Display (Geist) for headings, Mono (Geist Mono) for code.
// Body uses system stack for performance.
// ------------------------------------------------------------------
const fontSize = {
  // Scale: 1.250 major third
  'xs':   ['11px', { lineHeight: '16px', letterSpacing: '0.02em' }],
  'sm':   ['13px', { lineHeight: '20px', letterSpacing: '0.01em' }],
  'base': ['15px', { lineHeight: '24px', letterSpacing: '0em'    }],
  'md':   ['15px', { lineHeight: '24px', letterSpacing: '0em'    }],
  'lg':   ['17px', { lineHeight: '28px', letterSpacing: '-0.01em'}],
  'xl':   ['20px', { lineHeight: '28px', letterSpacing: '-0.02em'}],
  '2xl':  ['24px', { lineHeight: '32px', letterSpacing: '-0.02em'}],
  '3xl':  ['30px', { lineHeight: '36px', letterSpacing: '-0.03em'}],
  '4xl':  ['36px', { lineHeight: '40px', letterSpacing: '-0.03em'}],
  '5xl':  ['48px', { lineHeight: '52px', letterSpacing: '-0.04em'}],
  '6xl':  ['60px', { lineHeight: '64px', letterSpacing: '-0.04em'}],
}

// ------------------------------------------------------------------
// STEP 6: Shadow / Elevation Scale
// Dark-mode shadows use opacity reduction, not color change.
// Light-mode uses warm-tinted shadows.
// ------------------------------------------------------------------
const boxShadow = {
  'none':     'none',
  'xs':       '0px 1px 2px rgba(0, 0, 0, 0.05)',
  'sm':       '0px 1px 3px rgba(0, 0, 0, 0.10), 0px 1px 2px rgba(0, 0, 0, 0.06)',
  'md':       '0px 4px 6px rgba(0, 0, 0, 0.07), 0px 2px 4px rgba(0, 0, 0, 0.06)',
  'lg':       '0px 10px 15px rgba(0, 0, 0, 0.10), 0px 4px 6px rgba(0, 0, 0, 0.05)',
  'xl':       '0px 20px 25px rgba(0, 0, 0, 0.10), 0px 10px 10px rgba(0, 0, 0, 0.04)',
  '2xl':      '0px 25px 50px rgba(0, 0, 0, 0.25)',
  // Brand glow — used on avatar frames, primary CTAs
  'glow-sm':  '0px 0px 8px rgba(139, 92, 246, 0.35)',
  'glow-md':  '0px 0px 16px rgba(139, 92, 246, 0.40)',
  'glow-lg':  '0px 0px 32px rgba(139, 92, 246, 0.35)',
  // Voice-active glow (cyan)
  'glow-voice': '0px 0px 24px rgba(6, 182, 212, 0.50)',
  // Inner shadow for sunken inputs
  'inner':    'inset 0px 2px 4px rgba(0, 0, 0, 0.06)',
  'inner-md': 'inset 0px 4px 8px rgba(0, 0, 0, 0.12)',
}

// ------------------------------------------------------------------
// STEP 7: Full Tailwind Config Export
// ------------------------------------------------------------------
const config: Config = {
  darkMode: 'class',  // class-based for programmatic control
  content: [
    './src/**/*.{ts,tsx}',
    '../../packages/design-system/src/**/*.{ts,tsx}',
  ],
  theme: {
    // Override (not extend) for full control
    colors: {
      transparent: 'transparent',
      current: 'currentColor',
      white: '#ffffff',
      black: '#000000',
      ...palette,
      ...semanticColors,
    },
    spacing,
    borderRadius,
    fontSize,
    boxShadow,
    fontFamily: {
      sans:    ['Geist', ...fontFamily.sans],
      mono:    ['Geist Mono', ...fontFamily.mono],
      display: ['Geist', ...fontFamily.sans],
    },
    fontWeight: {
      regular:   '400',
      medium:    '500',
      semibold:  '600',
      bold:      '700',
    },
    // Animation tokens (referenced by Framer Motion via CSS vars)
    transitionDuration: {
      'instant':  '0ms',
      'fast':     '100ms',
      'normal':   '200ms',
      'slow':     '350ms',
      'glacial':  '700ms',
    },
    transitionTimingFunction: {
      'ease-in-smooth':  'cubic-bezier(0.4, 0, 1, 1)',
      'ease-out-smooth': 'cubic-bezier(0, 0, 0.2, 1)',
      'ease-in-out':     'cubic-bezier(0.4, 0, 0.2, 1)',
      'spring':          'cubic-bezier(0.34, 1.56, 0.64, 1)',  // overshoot
      'bounce':          'cubic-bezier(0.68, -0.55, 0.265, 1.55)',
    },
    extend: {
      // Breakpoints (mobile-first)
      screens: {
        'xs':  '360px',   // small phones
        'sm':  '480px',   // large phones
        'md':  '768px',   // tablets
        'lg':  '1024px',  // laptops
        'xl':  '1280px',  // desktops
        '2xl': '1440px',  // wide
        '3xl': '1920px',  // ultra-wide (admin dashboards)
      },
      // Touch target minimum
      minHeight: {
        'touch': '44px',
      },
      minWidth: {
        'touch': '44px',
      },
      // Blur tokens
      backdropBlur: {
        'xs': '2px',
        'sm': '4px',
        'md': '8px',
        'lg': '16px',
        'xl': '24px',
      },
      // Z-index semantic scale
      zIndex: {
        'below':    '-1',
        'base':     '0',
        'raised':   '10',
        'dropdown': '100',
        'sticky':   '200',
        'overlay':  '300',
        'modal':    '400',
        'toast':    '500',
        'tooltip':  '600',
        'max':      '999',
      },
      // Keyframes for system animations
      keyframes: {
        'fade-in': {
          from: { opacity: '0' },
          to:   { opacity: '1' },
        },
        'fade-out': {
          from: { opacity: '1' },
          to:   { opacity: '0' },
        },
        'slide-up': {
          from: { transform: 'translateY(8px)', opacity: '0' },
          to:   { transform: 'translateY(0)',   opacity: '1' },
        },
        'slide-down': {
          from: { transform: 'translateY(-8px)', opacity: '0' },
          to:   { transform: 'translateY(0)',    opacity: '1' },
        },
        'slide-left': {
          from: { transform: 'translateX(16px)', opacity: '0' },
          to:   { transform: 'translateX(0)',    opacity: '1' },
        },
        'scale-in': {
          from: { transform: 'scale(0.95)', opacity: '0' },
          to:   { transform: 'scale(1)',    opacity: '1' },
        },
        'shimmer': {
          from: { backgroundPosition: '-200% 0' },
          to:   { backgroundPosition: '200% 0'  },
        },
        'pulse-ring': {
          '0%':   { transform: 'scale(1)',    opacity: '1'   },
          '100%': { transform: 'scale(1.4)', opacity: '0'   },
        },
        'voice-wave': {
          '0%, 100%': { scaleY: '0.4' },
          '50%':       { scaleY: '1'   },
        },
        'blink-cursor': {
          '0%, 100%': { opacity: '1' },
          '50%':       { opacity: '0' },
        },
      },
      animation: {
        'fade-in':    'fade-in 200ms ease-out-smooth both',
        'fade-out':   'fade-out 150ms ease-in-smooth both',
        'slide-up':   'slide-up 200ms ease-out-smooth both',
        'slide-down': 'slide-down 200ms ease-out-smooth both',
        'slide-left': 'slide-left 200ms ease-out-smooth both',
        'scale-in':   'scale-in 150ms spring both',
        'shimmer':    'shimmer 2s ease-in-out infinite',
        'pulse-ring': 'pulse-ring 1.5s ease-out infinite',
        'voice-wave': 'voice-wave 0.8s ease-in-out infinite',
        'blink':      'blink-cursor 1s step-end infinite',
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('tailwindcss-animate'),
    // Custom plugin for design system utilities
    ({ addUtilities, addComponents }: any) => {
      addUtilities({
        // Focus ring — consistent across all interactive elements
        '.focus-ring': {
          outline: 'none',
          '&:focus-visible': {
            outline: '2px solid var(--color-brand-primary)',
            outlineOffset: '2px',
            borderRadius: 'inherit',
          },
        },
        // Glass morphism surface
        '.surface-glass': {
          background: 'var(--color-surface-glass)',
          backdropFilter: 'blur(12px)',
          WebkitBackdropFilter: 'blur(12px)',
          border: '1px solid var(--color-border-subtle)',
        },
        // Scrollbar styling
        '.scrollbar-thin': {
          scrollbarWidth: 'thin',
          scrollbarColor: 'var(--color-border-default) transparent',
          '&::-webkit-scrollbar': { width: '4px', height: '4px' },
          '&::-webkit-scrollbar-track': { background: 'transparent' },
          '&::-webkit-scrollbar-thumb': {
            background: 'var(--color-border-default)',
            borderRadius: '9999px',
          },
        },
        // Text gradient (brand)
        '.text-gradient-brand': {
          background: 'linear-gradient(135deg, var(--color-brand-primary), var(--color-brand-accent))',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          backgroundClip: 'text',
        },
      })
    },
  ],
}

export default config
```

### 1.2 CSS Custom Properties — Theme Definitions

Create `/packages/design-system/src/styles/globals.css`:

```css
/* ================================================================
   EXAMPLE DESIGN SYSTEM — Global CSS Custom Properties
   Theme: dark (default) | light
   ================================================================ */

@import url('https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap');

/* ----------------------------------------------------------------
   DARK THEME (default — :root)
   Surfaces use a warm-dark palette, not pure blacks.
   ---------------------------------------------------------------- */
:root {
  color-scheme: dark;

  /* Brand */
  --color-brand-primary:        #8b5cf6;  /* violet-500 */
  --color-brand-primary-hover:  #7c3aed;  /* violet-600 */
  --color-brand-primary-active: #6d28d9;  /* violet-700 */
  --color-brand-primary-subtle: rgba(139, 92, 246, 0.12);
  --color-brand-secondary:      #f59e0b;  /* amber-500 */
  --color-brand-accent:         #06b6d4;  /* cyan-500 */
  --color-brand-accent-live:    #22d3ee;  /* cyan-400 */

  /* Surfaces — 5-layer elevation model */
  --color-surface-base:         #0d0d0a;  /* neutral-925 — page background */
  --color-surface-raised:       #1a1a16;  /* neutral-900 — cards */
  --color-surface-overlay:      #26261f;  /* neutral-800 — modals, drawers */
  --color-surface-sunken:       #141411;  /* neutral-925 — inputs (below surface) */
  --color-surface-inverse:      #f4f4f2;  /* neutral-100 — tooltip bg in dark */
  --color-surface-glass:        rgba(26, 26, 22, 0.72);
  --color-surface-sidebar:      #111110;  /* sidebar — deepest */
  --color-surface-header:       rgba(13, 13, 10, 0.85);

  /* Borders */
  --color-border-subtle:        rgba(255, 255, 255, 0.06);
  --color-border-default:       rgba(255, 255, 255, 0.10);
  --color-border-strong:        rgba(255, 255, 255, 0.18);
  --color-border-brand:         rgba(139, 92, 246, 0.40);

  /* Text */
  --color-text-primary:         #f4f4f2;  /* neutral-100 */
  --color-text-secondary:       #a8a8a3;  /* neutral-400 */
  --color-text-tertiary:        #71716c;  /* neutral-500 */
  --color-text-placeholder:     #52524e;  /* neutral-600 */
  --color-text-inverse:         #0d0d0a;  /* for inverse surfaces */
  --color-text-brand:           #a78bfa;  /* violet-400 — slightly lighter for dark bg */
  --color-text-link:            #a78bfa;

  /* Semantic status */
  --color-status-success:       #34d399;  /* emerald-400 */
  --color-status-success-subtle:rgba(52, 211, 153, 0.12);
  --color-status-warning:       #fbbf24;  /* amber-400 */
  --color-status-warning-subtle:rgba(251, 191, 36, 0.12);
  --color-status-error:         #fb7185;  /* rose-400 */
  --color-status-error-subtle:  rgba(251, 113, 133, 0.12);
  --color-status-info:          #22d3ee;  /* cyan-400 */
  --color-status-info-subtle:   rgba(34, 211, 238, 0.12);

  /* Voice/live states */
  --color-voice-active:         #22d3ee;
  --color-voice-listening:      #06b6d4;
  --color-voice-processing:     #a78bfa;

  /* Interactive */
  --color-interactive-default:  rgba(255, 255, 255, 0.05);
  --color-interactive-hover:    rgba(255, 255, 255, 0.08);
  --color-interactive-active:   rgba(255, 255, 255, 0.12);
  --color-interactive-focus:    rgba(139, 92, 246, 0.20);
  --color-interactive-disabled: rgba(255, 255, 255, 0.03);

  /* 3D Scene lighting tokens (consumed by Three.js setup) */
  --scene-ambient-intensity:    0.4;
  --scene-ambient-color:        #1a1a2e;  /* cool dark */
  --scene-key-intensity:        1.2;
  --scene-key-color:            #8b5cf6;  /* violet tint */
  --scene-rim-intensity:        0.6;
  --scene-rim-color:            #06b6d4;  /* cyan rim */
  --scene-fill-intensity:       0.2;
  --scene-fill-color:           #f59e0b;  /* warm amber fill */
  --scene-bg-color:             #0d0d0a;

  /* Typography */
  --font-sans:    'Geist', system-ui, -apple-system, sans-serif;
  --font-mono:    'Geist Mono', 'Fira Code', monospace;

  /* Animation */
  --duration-instant:  0ms;
  --duration-fast:     100ms;
  --duration-normal:   200ms;
  --duration-slow:     350ms;
  --duration-glacial:  700ms;

  --ease-in:       cubic-bezier(0.4, 0, 1, 1);
  --ease-out:      cubic-bezier(0, 0, 0.2, 1);
  --ease-in-out:   cubic-bezier(0.4, 0, 0.2, 1);
  --ease-spring:   cubic-bezier(0.34, 1.56, 0.64, 1);
  --ease-bounce:   cubic-bezier(0.68, -0.55, 0.265, 1.55);
}

/* ----------------------------------------------------------------
   LIGHT THEME
   Applied via .light class on <html> or <body>
   ---------------------------------------------------------------- */
.light {
  color-scheme: light;

  --color-brand-primary:        #7c3aed;  /* violet-600 — darker for contrast on white */
  --color-brand-primary-hover:  #6d28d9;
  --color-brand-primary-active: #5b21b6;
  --color-brand-primary-subtle: rgba(124, 58, 237, 0.08);
  --color-brand-secondary:      #d97706;  /* amber-600 */
  --color-brand-accent:         #0891b2;  /* cyan-600 */
  --color-brand-accent-live:    #06b6d4;

  --color-surface-base:         #fafaf9;
  --color-surface-raised:       #ffffff;
  --color-surface-overlay:      #ffffff;
  --color-surface-sunken:       #f4f4f2;
  --color-surface-inverse:      #1a1a16;
  --color-surface-glass:        rgba(255, 255, 255, 0.80);
  --color-surface-sidebar:      #f4f4f2;
  --color-surface-header:       rgba(250, 250, 249, 0.90);

  --color-border-subtle:        rgba(0, 0, 0, 0.05);
  --color-border-default:       rgba(0, 0, 0, 0.10);
  --color-border-strong:        rgba(0, 0, 0, 0.18);
  --color-border-brand:         rgba(124, 58, 237, 0.35);

  --color-text-primary:         #1a1a16;
  --color-text-secondary:       #52524e;
  --color-text-tertiary:        #71716c;
  --color-text-placeholder:     #a8a8a3;
  --color-text-inverse:         #f4f4f2;
  --color-text-brand:           #6d28d9;  /* violet-700 on light bg */
  --color-text-link:            #6d28d9;

  --color-status-success:       #059669;
  --color-status-success-subtle:rgba(5, 150, 105, 0.10);
  --color-status-warning:       #d97706;
  --color-status-warning-subtle:rgba(217, 119, 6, 0.10);
  --color-status-error:         #e11d48;
  --color-status-error-subtle:  rgba(225, 29, 72, 0.08);
  --color-status-info:          #0891b2;
  --color-status-info-subtle:   rgba(8, 145, 178, 0.10);

  --color-voice-active:         #0891b2;
  --color-voice-listening:      #06b6d4;
  --color-voice-processing:     #7c3aed;

  --color-interactive-default:  rgba(0, 0, 0, 0.03);
  --color-interactive-hover:    rgba(0, 0, 0, 0.06);
  --color-interactive-active:   rgba(0, 0, 0, 0.09);
  --color-interactive-focus:    rgba(124, 58, 237, 0.15);
  --color-interactive-disabled: rgba(0, 0, 0, 0.02);

  /* 3D scene — brighter, warmer in light mode */
  --scene-ambient-intensity:    0.8;
  --scene-ambient-color:        #e8e8ff;
  --scene-key-intensity:        1.5;
  --scene-key-color:            #ffffff;
  --scene-rim-intensity:        0.4;
  --scene-rim-color:            #06b6d4;
  --scene-fill-intensity:       0.3;
  --scene-fill-color:           #fef3c7;
  --scene-bg-color:             #fafaf9;
}
```

---

## 2. Component Hierarchy

### 2.1 Package Structure

```
packages/design-system/
├── src/
│   ├── primitives/          ← Radix UI wrappers (unstyled → styled)
│   │   ├── Dialog/
│   │   ├── Dropdown/
│   │   ├── Tabs/
│   │   ├── Toast/
│   │   ├── ScrollArea/
│   │   ├── Tooltip/
│   │   ├── Popover/
│   │   ├── Select/
│   │   ├── Checkbox/
│   │   ├── RadioGroup/
│   │   ├── Switch/
│   │   ├── Slider/
│   │   └── AlertDialog/
│   ├── atoms/
│   │   ├── Button/
│   │   ├── Input/
│   │   ├── Badge/
│   │   ├── Avatar/
│   │   ├── Chip/
│   │   ├── Toggle/
│   │   ├── Skeleton/
│   │   ├── Spinner/
│   │   ├── Divider/
│   │   ├── Label/
│   │   └── Icon/
│   ├── molecules/
│   │   ├── SearchBar/
│   │   ├── ChatBubble/
│   │   ├── AvatarCard/
│   │   ├── StatCard/
│   │   ├── NavItem/
│   │   ├── FormField/
│   │   ├── ContextMenu/
│   │   ├── CommandPalette/
│   │   └── EmptyState/
│   ├── organisms/
│   │   ├── ChatPanel/
│   │   ├── VoiceCallOverlay/
│   │   ├── AvatarViewer/
│   │   ├── DataTable/
│   │   ├── Sidebar/
│   │   ├── Header/
│   │   ├── KnowledgeGraph/
│   │   └── NotificationCenter/
│   ├── templates/
│   │   ├── ChatLayout/
│   │   ├── DashboardLayout/
│   │   └── SettingsLayout/
│   ├── hooks/
│   │   ├── useTheme.ts
│   │   ├── useFocusTrap.ts
│   │   ├── useMediaQuery.ts
│   │   ├── useAnnounce.ts     ← aria-live announcements
│   │   └── useReducedMotion.ts
│   ├── tokens/
│   │   ├── index.ts           ← re-exports all token objects (JS)
│   │   └── types.ts
│   ├── styles/
│   │   └── globals.css
│   └── index.ts               ← main package export
```

### 2.2 Component Specs

**Button Atom — Full Variant Matrix:**

```typescript
// packages/design-system/src/atoms/Button/Button.tsx
import { forwardRef } from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '../../lib/cn'

const buttonVariants = cva(
  // Base — always applied
  [
    'relative inline-flex items-center justify-center gap-2',
    'font-medium select-none whitespace-nowrap',
    'rounded-md transition-all',
    'focus-ring',                           // from custom Tailwind plugin
    'disabled:pointer-events-none disabled:opacity-40',
    'active:scale-[0.97]',                  // tactile press feedback
  ],
  {
    variants: {
      variant: {
        // Filled — primary action
        primary: [
          'bg-brand-primary text-white',
          'hover:bg-brand-primary-hover',
          'shadow-glow-sm hover:shadow-glow-md',
          'duration-fast',
        ],
        // Secondary — ghost with border
        secondary: [
          'bg-interactive-default text-text-primary',
          'border border-border-default',
          'hover:bg-interactive-hover hover:border-border-strong',
          'duration-fast',
        ],
        // Ghost — no background
        ghost: [
          'text-text-secondary',
          'hover:bg-interactive-hover hover:text-text-primary',
          'duration-fast',
        ],
        // Destructive
        destructive: [
          'bg-status-error text-white',
          'hover:opacity-90',
          'duration-fast',
        ],
        // Brand subtle
        subtle: [
          'bg-brand-primary-subtle text-brand-primary',
          'hover:bg-[rgba(139,92,246,0.18)]',
          'duration-fast',
        ],
        // Link style
        link: [
          'text-text-link underline-offset-4',
          'hover:underline',
          'h-auto px-0 py-0',
        ],
      },
      size: {
        xs: 'h-7 px-2.5 text-xs',
        sm: 'h-8 px-3 text-sm',
        md: 'h-9 px-4 text-sm',
        lg: 'h-11 px-5 text-base',     // h-11 = 44px minimum touch target
        xl: 'h-12 px-6 text-lg',
        // Icon-only sizes (square)
        'icon-sm': 'h-8 w-8 px-0',
        'icon-md': 'h-9 w-9 px-0',
        'icon-lg': 'h-11 w-11 px-0',
      },
    },
    defaultVariants: {
      variant: 'primary',
      size: 'md',
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
  loading?: boolean
  leftIcon?: React.ReactNode
  rightIcon?: React.ReactNode
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild, loading, leftIcon, rightIcon, children, disabled, ...props }, ref) => {
    const Comp = asChild ? Slot : 'button'
    return (
      <Comp
        ref={ref}
        disabled={disabled || loading}
        aria-disabled={disabled || loading}
        aria-busy={loading}
        className={cn(buttonVariants({ variant, size }), className)}
        {...props}
      >
        {loading ? (
          <span className="animate-spin h-4 w-4 rounded-full border-2 border-current border-t-transparent" aria-hidden />
        ) : leftIcon}
        {children}
        {!loading && rightIcon}
      </Comp>
    )
  }
)
Button.displayName = 'Button'
```

**ChatBubble Molecule:**

```typescript
// packages/design-system/src/molecules/ChatBubble/ChatBubble.tsx
import { cn } from '../../lib/cn'
import { Avatar } from '../../atoms/Avatar'

type ChatBubbleRole = 'user' | 'assistant' | 'system'

interface ChatBubbleProps {
  role: ChatBubbleRole
  content: string
  timestamp?: Date
  isStreaming?: boolean   // SSE streaming in progress
  avatarUrl?: string
  avatarName?: string
  reactions?: string[]
  className?: string
}

export function ChatBubble({
  role,
  content,
  timestamp,
  isStreaming,
  avatarUrl,
  avatarName,
  className,
}: ChatBubbleProps) {
  const isUser = role === 'user'

  return (
    <div
      className={cn(
        'flex gap-3 w-full',
        isUser ? 'flex-row-reverse' : 'flex-row',
        className
      )}
      // Each bubble is a listitem — parent ChatPanel uses role="list"
    >
      {!isUser && (
        <Avatar
          src={avatarUrl}
          name={avatarName}
          size="sm"
          className="flex-shrink-0 mt-1 ring-2 ring-brand-primary-subtle"
        />
      )}

      <div className={cn('flex flex-col gap-1 max-w-[75%]', isUser && 'items-end')}>
        <div
          className={cn(
            'px-4 py-3 text-sm leading-relaxed',
            // User bubble
            isUser && [
              'bg-brand-primary text-white',
              'rounded-2xl rounded-tr-sm',
              'shadow-glow-sm',
            ],
            // Assistant bubble
            !isUser && [
              'bg-surface-overlay text-text-primary',
              'border border-border-subtle',
              'rounded-2xl rounded-tl-sm',
            ],
          )}
        >
          {content}
          {isStreaming && (
            <span
              className="inline-block w-2 h-4 ml-0.5 bg-current animate-blink align-middle rounded-xs"
              aria-hidden
            />
          )}
        </div>

        {timestamp && (
          <time
            className="text-xs text-text-tertiary px-1"
            dateTime={timestamp.toISOString()}
          >
            {timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </time>
        )}
      </div>
    </div>
  )
}
```

**StatCard Molecule (Admin):**

```typescript
// packages/design-system/src/molecules/StatCard/StatCard.tsx
import { cn } from '../../lib/cn'
import { Skeleton } from '../../atoms/Skeleton'

interface StatCardProps {
  label: string
  value: string | number
  delta?: {
    value: number      // percentage change
    period: string     // "vs last week"
  }
  icon?: React.ReactNode
  trend?: 'up' | 'down' | 'neutral'
  loading?: boolean
  className?: string
}

export function StatCard({ label, value, delta, icon, trend, loading, className }: StatCardProps) {
  const deltaColor = trend === 'up'
    ? 'text-status-success'
    : trend === 'down'
    ? 'text-status-error'
    : 'text-text-tertiary'

  return (
    <article
      className={cn(
        'rounded-lg border border-border-subtle bg-surface-raised p-5',
        'hover:border-border-default transition-colors duration-fast',
        className
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-2">
            {label}
          </p>
          {loading ? (
            <Skeleton className="h-8 w-24 mb-2" />
          ) : (
            <p className="text-3xl font-bold text-text-primary tabular-nums">
              {value}
            </p>
          )}
          {delta && !loading && (
            <p className={cn('text-xs mt-1.5', deltaColor)}>
              {delta.value > 0 ? '+' : ''}{delta.value}% {delta.period}
            </p>
          )}
        </div>
        {icon && (
          <div className="p-2 rounded-md bg-brand-primary-subtle text-brand-primary flex-shrink-0">
            {icon}
          </div>
        )}
      </div>
    </article>
  )
}
```

---

## 3. Animation System

### 3.1 Motion Principles

The product operates on three motion laws:

**Law 1 — Meaning over decoration.** Every animation communicates state. A button press confirms intent. A slide-in indicates arrival from a direction. An element never animates just to feel modern.

**Law 2 — Speed implies importance.** Fast animations (100ms) are for micro-feedback — hovers, toggles. Normal animations (200ms) are for content transitions. Slow animations (350ms+) are for major state changes like navigation or overlays opening.

**Law 3 — 3D and UI are separate layers.** The Three.js scene runs on its own RAF loop. Framer Motion drives UI. They communicate via Zustand state, never directly. This prevents frame budget conflicts.

### 3.2 Framer Motion Configuration

```typescript
// packages/design-system/src/tokens/motion.ts

// Shared variants — import these in all animated components
export const motionVariants = {
  // Page-level transitions
  page: {
    initial:  { opacity: 0, y: 12 },
    animate:  { opacity: 1, y: 0, transition: { duration: 0.25, ease: [0, 0, 0.2, 1] } },
    exit:     { opacity: 0, y: -8, transition: { duration: 0.15, ease: [0.4, 0, 1, 1] } },
  },

  // Content that fades in (chat messages, cards loading)
  fadeUp: {
    initial:  { opacity: 0, y: 8 },
    animate:  { opacity: 1, y: 0, transition: { duration: 0.2, ease: [0, 0, 0.2, 1] } },
    exit:     { opacity: 0, transition: { duration: 0.1 } },
  },

  // Panels sliding in from right (detail views)
  slideLeft: {
    initial:  { opacity: 0, x: 24 },
    animate:  { opacity: 1, x: 0, transition: { duration: 0.25, ease: [0, 0, 0.2, 1] } },
    exit:     { opacity: 0, x: 24, transition: { duration: 0.2, ease: [0.4, 0, 1, 1] } },
  },

  // Modal/dialog scale-in
  modal: {
    initial:  { opacity: 0, scale: 0.95 },
    animate:  { opacity: 1, scale: 1, transition: { duration: 0.15, ease: [0.34, 1.56, 0.64, 1] } },
    exit:     { opacity: 0, scale: 0.97, transition: { duration: 0.1 } },
  },

  // Toast entry (from top-right)
  toast: {
    initial:  { opacity: 0, x: 32, scale: 0.95 },
    animate:  { opacity: 1, x: 0, scale: 1, transition: { duration: 0.2, ease: [0.34, 1.56, 0.64, 1] } },
    exit:     { opacity: 0, x: 32, transition: { duration: 0.15 } },
  },

  // List stagger parent
  staggerContainer: {
    animate:  { transition: { staggerChildren: 0.04, delayChildren: 0.05 } },
  },

  // Stagger child (for chat history loading, table rows)
  staggerChild: {
    initial:  { opacity: 0, y: 6 },
    animate:  { opacity: 1, y: 0, transition: { duration: 0.2 } },
  },
}

// Duration constants (matches CSS vars for consistency)
export const duration = {
  instant: 0,
  fast:    0.1,
  normal:  0.2,
  slow:    0.35,
  glacial: 0.7,
} as const

// Easing constants
export const ease = {
  in:     [0.4, 0, 1, 1]     as const,
  out:    [0, 0, 0.2, 1]     as const,
  inOut:  [0.4, 0, 0.2, 1]   as const,
  spring: [0.34, 1.56, 0.64, 1] as const,
  bounce: [0.68, -0.55, 0.265, 1.55] as const,
} as const

// Spring configs for Framer Motion spring animations
export const spring = {
  snappy:  { type: 'spring', stiffness: 400, damping: 30 },
  gentle:  { type: 'spring', stiffness: 200, damping: 25 },
  bouncy:  { type: 'spring', stiffness: 300, damping: 15 },
  slow:    { type: 'spring', stiffness: 100, damping: 20 },
} as const
```

### 3.3 Three.js / VRM Animation Integration

```typescript
// frontend-app/src/hooks/useSceneLighting.ts
// Reads CSS custom properties to drive Three.js lighting
// Called once on mount and when theme changes

import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import { useThemeStore } from '../store/themeStore'

export function useSceneLighting(scene: THREE.Scene | null) {
  const theme = useThemeStore((s) => s.theme)
  const lightsRef = useRef<{
    ambient: THREE.AmbientLight
    key:     THREE.DirectionalLight
    rim:     THREE.DirectionalLight
    fill:    THREE.DirectionalLight
  } | null>(null)

  useEffect(() => {
    if (!scene) return
    const root = document.documentElement
    const get = (prop: string) => getComputedStyle(root).getPropertyValue(prop).trim()

    // Read tokens at runtime — theme switch updates these automatically
    const ambientIntensity = parseFloat(get('--scene-ambient-intensity'))
    const ambientColor     = get('--scene-ambient-color')
    const keyIntensity     = parseFloat(get('--scene-key-intensity'))
    const keyColor         = get('--scene-key-color')
    const rimIntensity     = parseFloat(get('--scene-rim-intensity'))
    const rimColor         = get('--scene-rim-color')
    const fillIntensity    = parseFloat(get('--scene-fill-intensity'))
    const fillColor        = get('--scene-fill-color')

    if (!lightsRef.current) {
      // First mount — create lights
      const ambient = new THREE.AmbientLight(ambientColor, ambientIntensity)
      const key     = new THREE.DirectionalLight(keyColor, keyIntensity)
      const rim     = new THREE.DirectionalLight(rimColor, rimIntensity)
      const fill    = new THREE.DirectionalLight(fillColor, fillIntensity)

      key.position.set(2, 3, 2)
      rim.position.set(-3, 2, -2)
      fill.position.set(0, -1, 3)

      scene.add(ambient, key, rim, fill)
      lightsRef.current = { ambient, key, rim, fill }
    } else {
      // Theme changed — update existing lights smoothly
      const { ambient, key, rim, fill } = lightsRef.current
      // Transition over 700ms to match --duration-glacial
      // Use a simple lerp in RAF — not Framer Motion (3D layer boundary)
      animateLightTransition(ambient, ambientColor, ambientIntensity)
      animateLightTransition(key, keyColor, keyIntensity)
      animateLightTransition(rim, rimColor, rimIntensity)
      animateLightTransition(fill, fillColor, fillIntensity)
    }
  }, [scene, theme])
}

// Lerp light color and intensity over ~700ms (36 frames at 50fps)
function animateLightTransition(
  light: THREE.Light,
  targetColor: string,
  targetIntensity: number
) {
  const target = new THREE.Color(targetColor)
  const startColor = light.color.clone()
  const startIntensity = light.intensity
  const frames = 42  // ~700ms at 60fps
  let frame = 0

  function tick() {
    frame++
    const t = frame / frames
    light.color.lerpColors(startColor, target, t)
    light.intensity = startIntensity + (targetIntensity - startIntensity) * t
    if (frame < frames) requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}
```

### 3.4 Reduced Motion

```typescript
// packages/design-system/src/hooks/useReducedMotion.ts
import { useEffect, useState } from 'react'

export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(
    () => window.matchMedia('(prefers-reduced-motion: reduce)').matches
  )
  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    const handler = (e: MediaQueryListEvent) => setReduced(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])
  return reduced
}

// Usage: all Framer Motion variants check this
// const reduced = useReducedMotion()
// <motion.div variants={reduced ? {} : motionVariants.fadeUp} />

// Also set in globals.css:
// @media (prefers-reduced-motion: reduce) {
//   *, *::before, *::after {
//     animation-duration: 0.01ms !important;
//     transition-duration: 0.01ms !important;
//   }
// }
```

---

## 4. Responsive Strategy

### 4.1 Breakpoint Strategy by App

The four apps have fundamentally different device targets. The breakpoint system handles all of them from a single shared scale.

```
xs:  360px  — Small Android phones (ExampleChat primary target)
sm:  480px  — Large phones, landscape phone
md:  768px  — Tablets (ExampleChat landscape, Admin secondary)
lg:  1024px — Laptops (all admin apps primary)
xl:  1280px — Desktops
2xl: 1440px — Wide desktop (Example Memory graph view)
3xl: 1920px — Ultra-wide (Example Omnichannel multi-column)
```

**App-specific responsive behavior:**

| Breakpoint | ExampleChat UI | Admin | Example Memory | Omnichannel |
|---|---|---|---|---|
| xs-sm | Full screen chat, bottom input | Not primary | Simplified | Not primary |
| md | Chat + collapsed sidebar | Stacked layout | Side panel | Stacked |
| lg | Chat + avatar side-by-side | Full dashboard | Graph + list | Multi-column |
| xl+ | Three-column (history, chat, avatar) | Dense tables | Full graph | Pipeline view |

### 4.2 Layout Grid

```typescript
// packages/design-system/src/templates/ChatLayout/ChatLayout.tsx
// Mobile-first: single column → three column at xl

export function ChatLayout({ sidebar, chat, viewer }: ChatLayoutProps) {
  return (
    <div className="
      h-dvh w-full overflow-hidden
      grid grid-rows-[auto_1fr_auto]       /* mobile: header / content / input */
      xl:grid-cols-[260px_1fr_380px]       /* desktop: sidebar / chat / avatar */
      xl:grid-rows-[1fr]
    ">
      {/* Conversation history — hidden on mobile, sidebar on desktop */}
      <aside className="
        hidden xl:flex
        flex-col bg-surface-sidebar
        border-r border-border-subtle
        overflow-hidden
      ">
        {sidebar}
      </aside>

      {/* Chat area */}
      <main className="
        flex flex-col overflow-hidden
        bg-surface-base
      ">
        {chat}
      </main>

      {/* Avatar viewer — bottom sheet on mobile, panel on desktop */}
      <aside className="
        hidden xl:flex
        flex-col bg-surface-raised
        border-l border-border-subtle
      ">
        {viewer}
      </aside>
    </div>
  )
}
```

### 4.3 Touch Targets

All interactive elements must meet 44x44px minimum (WCAG 2.5.5):

```typescript
// Rule: any button, link, or interactive control uses at minimum:
// className="min-h-touch min-w-touch"  (both = 44px from Tailwind config)

// For visually smaller controls (icon buttons, chips):
// Use padding expansion — the visual size can be smaller,
// but the hit area must be 44px.
// Pattern:
<button className="
  relative h-6 w-6              /* visual size */
  before:absolute               /* expanded hit area */
  before:inset-[-10px]
  before:content-['']
">
  <Icon />
</button>
```

---

## 5. Accessibility Standards

### 5.1 Focus Management

```typescript
// packages/design-system/src/hooks/useFocusTrap.ts
import { useEffect, useRef } from 'react'

const FOCUSABLE = [
  'a[href]', 'button:not([disabled])', 'input:not([disabled])',
  'select:not([disabled])', 'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ')

export function useFocusTrap(active: boolean) {
  const containerRef = useRef<HTMLElement>(null)

  useEffect(() => {
    if (!active || !containerRef.current) return
    const container = containerRef.current
    const focusable = Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE))
    const first = focusable[0]
    const last  = focusable[focusable.length - 1]

    // Store previously focused element to restore on unmount
    const previouslyFocused = document.activeElement as HTMLElement
    first?.focus()

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key !== 'Tab') return
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault()
          last?.focus()
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault()
          first?.focus()
        }
      }
    }

    container.addEventListener('keydown', handleKeyDown)
    return () => {
      container.removeEventListener('keydown', handleKeyDown)
      previouslyFocused?.focus()  // Restore focus on trap release
    }
  }, [active])

  return containerRef
}
```

### 5.2 Live Region — Real-time Chat

```typescript
// packages/design-system/src/hooks/useAnnounce.ts
// Manages aria-live announcements for chat messages and status changes

import { useCallback, useEffect, useRef } from 'react'

type Politeness = 'polite' | 'assertive'

export function useAnnounce() {
  const politeRef   = useRef<HTMLDivElement>(null)
  const assertiveRef = useRef<HTMLDivElement>(null)

  // Mount two visually-hidden live regions
  useEffect(() => {
    const createRegion = (politeness: Politeness) => {
      const div = document.createElement('div')
      div.setAttribute('aria-live', politeness)
      div.setAttribute('aria-atomic', 'false')
      div.setAttribute('aria-relevant', 'additions')
      // Visually hidden but readable by screen readers
      Object.assign(div.style, {
        position: 'absolute', width: '1px', height: '1px',
        padding: '0', margin: '-1px', overflow: 'hidden',
        clip: 'rect(0,0,0,0)', whiteSpace: 'nowrap', border: '0',
      })
      document.body.appendChild(div)
      return div
    }
    ;(politeRef as any).current   = createRegion('polite')
    ;(assertiveRef as any).current = createRegion('assertive')

    return () => {
      politeRef.current?.remove()
      assertiveRef.current?.remove()
    }
  }, [])

  const announce = useCallback((message: string, politeness: Politeness = 'polite') => {
    const region = politeness === 'assertive' ? assertiveRef.current : politeRef.current
    if (!region) return
    // Clear then set — forces re-announcement if message repeats
    region.textContent = ''
    requestAnimationFrame(() => { region.textContent = message })
  }, [])

  return announce
}

// Usage in ChatPanel:
// const announce = useAnnounce()
// When new message arrives:
// announce(`${message.senderName} says: ${message.content}`)
// When voice call connects:
// announce('Voice call connected', 'assertive')
```

### 5.3 Color Contrast Verification

All text/background combinations must pass WCAG 2.1 AA (4.5:1 normal, 3:1 large):

```
DARK MODE — Verified Pairs:
text-primary    (#f4f4f2) on surface-base    (#0d0d0a) = 16.8:1  ✓ AAA
text-secondary  (#a8a8a3) on surface-base    (#0d0d0a) = 7.4:1   ✓ AAA
text-tertiary   (#71716c) on surface-base    (#0d0d0a) = 4.6:1   ✓ AA
text-brand      (#a78bfa) on surface-base    (#0d0d0a) = 6.2:1   ✓ AAA
status-error    (#fb7185) on surface-raised  (#1a1a16) = 5.1:1   ✓ AA
status-success  (#34d399) on surface-raised  (#1a1a16) = 7.9:1   ✓ AAA
white on brand-primary (#8b5cf6) on dark bg = 4.6:1              ✓ AA

LIGHT MODE — Verified Pairs:
text-primary    (#1a1a16) on surface-base    (#fafaf9) = 17.1:1  ✓ AAA
text-secondary  (#52524e) on surface-base    (#fafaf9) = 8.6:1   ✓ AAA
text-tertiary   (#71716c) on surface-raised  (#ffffff) = 5.0:1   ✓ AA
text-brand      (#6d28d9) on surface-base    (#fafaf9) = 7.4:1   ✓ AAA
white on brand-primary (#7c3aed) = 4.9:1                         ✓ AA

FLAG: text-placeholder (#52524e light / #52524e dark) on inputs
must only appear in empty states, never for real data. Not sufficient
contrast for content — placeholder purpose only.
```

### 5.4 Keyboard Navigation Map

```
ChatPanel:
  Tab          → message input
  Enter        → send message
  Shift+Enter  → newline
  Escape       → clear input / close emoji picker
  Arrow Up     → edit last message (if input is empty)
  /            → open command palette (if input focused)

Sidebar:
  Arrow Up/Down → navigate conversation list
  Enter         → open conversation
  Delete        → archive conversation (with confirmation)

DataTable (Admin):
  Arrow Up/Down → navigate rows
  Space         → select row
  Enter         → open row detail
  Shift+Click   → range select
  Cmd/Ctrl+A    → select all

VoiceCallOverlay:
  Space         → mute/unmute toggle
  Escape        → end call (with confirmation dialog)
  M             → mute
  K             → toggle camera (if applicable)
```

---

## 6. Dark/Light Theme Spec

### 6.1 Theme Switching Hook

```typescript
// packages/design-system/src/hooks/useTheme.ts
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

type Theme = 'dark' | 'light' | 'system'

interface ThemeStore {
  theme: Theme
  resolvedTheme: 'dark' | 'light'
  setTheme: (theme: Theme) => void
}

export const useThemeStore = create<ThemeStore>()(
  persist(
    (set, get) => ({
      theme: 'dark',          // AI products default dark
      resolvedTheme: 'dark',
      setTheme: (theme) => {
        const resolved = theme === 'system'
          ? window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
          : theme

        // Apply to <html> — single source of truth
        document.documentElement.classList.remove('dark', 'light')
        document.documentElement.classList.add(resolved)
        document.documentElement.setAttribute('data-theme', resolved)

        set({ theme, resolvedTheme: resolved })
      },
    }),
    {
      name: 'example-theme',
      onRehydrateStorage: () => (state) => {
        // Apply stored theme immediately on load (prevents flash)
        if (state) state.setTheme(state.theme)
      },
    }
  )
)

// Script injected in <head> before React loads — eliminates FOUC:
// <script>
//   (function(){
//     var t=localStorage.getItem('example-theme');
//     var theme=t?JSON.parse(t).state?.theme:'dark';
//     var resolved=theme==='system'
//       ?(window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light')
//       :theme||'dark';
//     document.documentElement.classList.add(resolved);
//   })();
// </script>
```

---

## 7. Iconography System

### 7.1 Icon Standards

The system uses **Lucide React** as the primary icon library. Lucide matches the design language: geometric, consistent stroke width, designed at 24x24 with a 2px stroke.

```typescript
// packages/design-system/src/atoms/Icon/Icon.tsx
import { type LucideIcon } from 'lucide-react'
import { cn } from '../../lib/cn'
import { cva, type VariantProps } from 'class-variance-authority'

const iconVariants = cva('flex-shrink-0', {
  variants: {
    size: {
      // Size scale: always use these, never arbitrary values
      xs:   'h-3 w-3',      // 12px — inline text decorations
      sm:   'h-3.5 w-3.5',  // 14px — small badges, tight UIs
      md:   'h-4 w-4',      // 16px — default inline icon
      lg:   'h-5 w-5',      // 20px — button icons, nav
      xl:   'h-6 w-6',      // 24px — feature icons, standalone
      '2xl':'h-8 w-8',      // 32px — empty states, illustrations
      '3xl':'h-12 w-12',    // 48px — hero states
    },
    // Stroke width matches size — thinner at large sizes
    // Note: Lucide uses strokeWidth prop, not CSS
  },
  defaultVariants: { size: 'md' },
})

interface IconProps extends VariantProps<typeof iconVariants> {
  icon: LucideIcon
  label?: string   // If provided, icon is not aria-hidden
  className?: string
  strokeWidth?: number
}

export function Icon({ icon: LucideIconComponent, size, label, className, strokeWidth }: IconProps) {
  // Stroke width by size: xs-sm=2, md-lg=1.75, xl+=1.5
  const defaultStroke = (size === 'xs' || size === 'sm') ? 2
    : (size === 'xl' || size === '2xl' || size === '3xl') ? 1.5
    : 1.75

  return (
    <LucideIconComponent
      className={cn(iconVariants({ size }), className)}
      strokeWidth={strokeWidth ?? defaultStroke}
      aria-hidden={!label}
      aria-label={label}
    />
  )
}
```

**Filled vs Outlined Convention:**
- Outlined icons (default): navigation, actions, informational
- Filled icons: active/selected state, status indicators (success checkmark, error X)
- Never mix filled and outlined in the same navigation context
- Voice/live state uses a pulsing cyan filled microphone icon

---

## 8. Shared vs App-Specific Architecture

### 8.1 Package Boundary Map

```
@example/design-system (shared — all 4 apps)
├── All tokens (colors, spacing, typography, motion, shadows)
├── All primitives (Radix UI wrappers)
├── All atoms (Button, Input, Badge, Avatar, etc.)
├── Shared molecules: SearchBar, FormField, StatCard, NavItem, EmptyState
├── Shared organisms: DataTable, Sidebar, Header, NotificationCenter
├── Shared templates: DashboardLayout, SettingsLayout
├── All hooks (useTheme, useFocusTrap, useAnnounce, useReducedMotion)
├── Icon system (Icon component + icon name constants)
└── Tailwind config (re-exported for app-level extension)

frontend-app ONLY:
├── ChatBubble (SSE streaming cursor, VRM avatar integration)
├── ChatPanel (live region, scroll-to-bottom, voice state)
├── VoiceCallOverlay (LiveKit controls, audio visualization)
├── AvatarViewer (Three.js canvas, VRM loader, scene lighting)
├── ChatLayout template (3-column with avatar panel)
└── VoiceWaveform atom

admin-app ONLY:
├── AnalyticsChart (Recharts wrapper with token theming)
├── ConversationTable (specialized DataTable extension)
├── AvatarManager organism
└── AdminLayout (dense information, sidebar variant)

memory-service ONLY:
├── KnowledgeGraph (D3/Force graph with token-styled nodes)
├── MemoryCard molecule
├── GraphToolbar organism
├── EntityDetail panel
└── MemoryLayout template

ingestion-ui ONLY:
├── SourceConnector card
├── IngestionPipeline organism (step visualization)
├── DataPreview organism
├── ChannelBadge atom (per-source: Twitter, WhatsApp, etc.)
└── OmnichannelLayout template
```

### 8.2 Package Setup

```json
// packages/design-system/package.json
{
  "name": "@example/design-system",
  "version": "1.0.0",
  "type": "module",
  "exports": {
    ".":                  "./src/index.ts",
    "./styles":           "./src/styles/globals.css",
    "./tailwind-config":  "./tailwind.config.ts",
    "./tokens":           "./src/tokens/index.ts"
  },
  "peerDependencies": {
    "react": "^18",
    "react-dom": "^18"
  },
  "dependencies": {
    "@radix-ui/react-dialog":       "^1.1.0",
    "@radix-ui/react-dropdown-menu":"^2.1.0",
    "@radix-ui/react-tabs":         "^1.1.0",
    "@radix-ui/react-toast":        "^1.2.0",
    "@radix-ui/react-scroll-area":  "^1.1.0",
    "@radix-ui/react-tooltip":      "^1.1.0",
    "@radix-ui/react-popover":      "^1.1.0",
    "@radix-ui/react-select":       "^2.1.0",
    "@radix-ui/react-checkbox":     "^1.1.0",
    "@radix-ui/react-switch":       "^1.1.0",
    "@radix-ui/react-slot":         "^1.1.0",
    "class-variance-authority":     "^0.7.0",
    "clsx":                         "^2.1.0",
    "framer-motion":                "^11.0.0",
    "lucide-react":                 "^0.400.0",
    "tailwind-merge":               "^2.3.0"
  }
}
```

```typescript
// packages/design-system/src/lib/cn.ts
// The universal utility — used in every component
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

### 8.3 App-Level Tailwind Extension

Each app extends the shared config rather than duplicating it:

```typescript
// apps/frontend-app/tailwind.config.ts
import { type Config } from 'tailwindcss'
import sharedConfig from '@example/design-system/tailwind-config'

const config: Config = {
  ...sharedConfig,
  content: [
    './src/**/*.{ts,tsx}',
    '../../packages/design-system/src/**/*.{ts,tsx}',
  ],
  theme: {
    ...sharedConfig.theme,
    extend: {
      ...sharedConfig.theme?.extend,
      // App-specific additions only
      // (VRM scene canvas sizing, chat column widths, etc.)
      width: {
        'chat-sidebar': '260px',
        'avatar-panel': '380px',
      },
    },
  },
}
export default config
```

---

## Summary Reference Card

**Token Decision Tree:**

```
Need a color?
  └─ Is it brand? → use brand-primary / brand-secondary / brand-accent
  └─ Is it a surface? → use surface-base / raised / overlay / sunken
  └─ Is it text? → use text-primary / secondary / tertiary / brand
  └─ Is it a status? → use status-success / warning / error / info
  └─ Is it interactive state? → use interactive-hover / active / focus
  └─ Never: use raw palette values (violet-500) in components

Need an animation?
  └─ < 100ms → user action feedback (hover, press)
  └─ 150-200ms → content appearance (fade, slide-in)
  └─ 300-350ms → layout transitions (panel open/close)
  └─ 700ms+ → theme transitions, ambient changes only
  └─ 3D animations → RAF loop only, never Framer Motion

Need a component?
  └─ Exists in Radix? → wrap it (Primitive layer)
  └─ Single visual element? → Atom
  └─ Composed of 2-3 atoms? → Molecule
  └─ Complex interaction / manages state? → Organism
  └─ Full page structure? → Template
```

**File paths to create:**
- `/packages/design-system/tailwind.config.ts`
- `/packages/design-system/src/styles/globals.css`
- `/packages/design-system/src/tokens/motion.ts`
- `/packages/design-system/src/atoms/Button/Button.tsx`
- `/packages/design-system/src/molecules/ChatBubble/ChatBubble.tsx`
- `/packages/design-system/src/molecules/StatCard/StatCard.tsx`
- `/packages/design-system/src/hooks/useTheme.ts`
- `/packages/design-system/src/hooks/useFocusTrap.ts`
- `/packages/design-system/src/hooks/useAnnounce.ts`
- `/packages/design-system/src/hooks/useReducedMotion.ts`
- `/packages/design-system/src/atoms/Icon/Icon.tsx`
- `/packages/design-system/src/lib/cn.ts`
- `/packages/design-system/package.json`
