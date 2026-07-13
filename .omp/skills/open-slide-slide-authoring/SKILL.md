---
name: open-slide-slide-authoring
description: "Technical reference for writing or editing pages in the live open-slide React app at ~/opt_data/open-slide/apps/demo (dev server on 0.0.0.0:5173). Use whenever about to write/edit any file under that project's slides/id/, including from open-slide-create-slide or open-slide-apply-comments, or for any ad-hoc slide edit. Covers file contract, 1920x1080 canvas rules, type scale, vertical-budget math, palette/design tokens, transitions, the self-review checklist, and how to QA a slide in the real dev server via the browser tool."
---

## Workspace

Project root: `/home/efsatu/opt_data/open-slide/apps/demo` (confirmed by the running dev server process — cwd contains `slides/`, `themes/`, `open-slide.config.ts`, `package.json`). Dev server: `http://0.0.0.0:5173` (or `http://localhost:5173`), started via `pnpm dev` from that directory. If it's not running, start it from there; don't run it from the monorepo root.

Before touching files, verify cwd/target actually is this project (has `slides/` + `open-slide.config.ts`) — if the user has multiple open-slide projects, confirm the right one.

This is the **technical reference** for everything inside `slides/<id>/index.tsx`. `open-slide-create-slide` owns the "draft a new deck" workflow and delegates the *how* here. `open-slide-apply-comments` finds inspector markers and applies edits following these rules. `open-slide-current-slide` resolves "this page"/"this slide" references to a concrete id first, then come back here for how to edit it.

## Hard rules

- Put the slide under `slides/<kebab-case-id>/`. Entry is `slides/<id>/index.tsx`. Images/videos/fonts under `slides/<id>/assets/`.
- Do **not** touch `package.json`, `open-slide.config.ts`, or other slides.
- Do not add dependencies. Only `react` and standard web APIs are available.
- A slide is **one `index.tsx` plus `assets/`** — nothing else. No sibling `.tsx`/`.ts` files, no `README.md`.

## File contract

```tsx
// slides/<id>/index.tsx
import type { Page, SlideMeta } from '@open-slide/core';

const Cover: Page = () => <div>…</div>;
const Body: Page = () => <div>…</div>;

export const meta: SlideMeta = {
  title: 'My slide',
  createdAt: '2026-05-16T12:00:00Z',
};
export default [Cover, Body] satisfies Page[];
```

- `export default` is a **non-empty array of zero-prop React components**, one per page, in order.
- `meta.title` (optional) shows in the slide header; default is the folder name.
- `meta.theme` (optional): id matching a `themes/<id>.md` basename — surfaces a back-link chip and lists the slide on `/themes/<id>`. Omit if not theme-derived.
- `meta.createdAt` is an ISO 8601 string literal, set once at creation. **Immediately before writing the file, run `node -e "console.log(new Date().toISOString())"` and paste the exact output** — don't type it from memory. Must be a plain string literal (framework reads it via regex at build time, not module evaluation).

## Editing an existing slide

Finished slides run 1000–1800 lines. Don't read the whole file to touch one page:

```bash
grep -n ": Page = " slides/<id>/index.tsx
```

Lists every `const Foo: Page = …` with line number. Read just that page with `offset`+`limit` (~150 lines usually covers one page + helpers). Read the whole file only for cross-page context (palette audit, reordering, design-const tweaks).

## Borrowing a visual identity from an existing slide (not a registered theme)

When the user says "make it look like slide X" and X is **not** one of the registered `themes/*.md` bundles, don't force the `open-slide-create-theme` workflow unless they explicitly want a reusable theme asset out of it. Instead, extract directly:

1. Find the slide: `grep -rn "title: '<approx title>'" slides/*/index.tsx` or grep the slide id if known.
2. Read its `design` const, standalone palette constants (bg/surface/text/muted/accent/tint colors), font stack, `@keyframes` block, and its `Eyebrow`/`Heading`/`Footer`/other fixed components.
3. Reuse those tokens and component shapes verbatim in the new slide's own `index.tsx` (own copies, not imports — slides can't import from each other) — same palette, same fonts, same footer/eyebrow visual pattern, renamed keyframes with a unique prefix (e.g. `btg-fadeUp` instead of `osa-fadeUp`) so multiple slides' injected `<style>` tags never collide by id.
4. **Prune the motion to match what was actually asked.** A rich reference slide (e.g. a framework-demo deck) often ships many keyframes (blink cursors, typewriter clip-path, shimmer, spin, dash-flow…) as a showcase. If the user asked for "subtle" or "smooth" motion, take only 2–3 keyframes (an entrance fade/rise, maybe a slow ambient glow pulse) and a single restrained `SlideTransition` — do not copy the full effect inventory just because the source slide has it.

## Canvas

Every page renders into a fixed **1920 × 1080** canvas — design as if the viewport literally is that size.

- Use **absolute pixel values** for font-size, padding, positioning. No `rem`, `vw`/`vh`, `%` for type.
- Root element of each page fills the canvas: `width: '100%'; height: '100%'`.
- Prefer inline `style={{ … }}`. Any loaded CSS is global — scope classnames carefully.

### Type scale (start here, adjust to taste)

| Element | Size |
|---|---|
| Hero title | 140–200px |
| Section heading | 80–120px |
| Page heading | 56–80px |
| Body text | 32–44px |
| Caption / label | 22–28px |

### Spacing

- Content padding: **100–160px** from canvas edges. Never let text touch the edge.
- Line-height: 1.2 headings, 1.5–1.7 body.
- Breathing room between elements: 32–64px.

### Vertical budget — content MUST fit 1080px (no scroll, ever)

The canvas does not scroll — anything past 1080px is silently cropped. This is the #1 cause of broken slides; assume overflow unless you've checked.

**Usable height** = `1080 − top_padding − bottom_padding`. 120px/side → 840px budget. 160px/side → 760px.

**Element height** = `font_size × line_height × number_of_lines` (a wrapped bullet counts as 2 lines). Add the gap below (32–64px) before summing the next element.

Worked example, 120px padding (840px budget):

| Element | Height |
|---|---|
| Heading: 80px × 1.2 × 1 line | 96px |
| Gap | 64px |
| Body paragraph: 40px × 1.6 × 3 lines | 192px |
| Gap | 48px |
| 5 bullets: 40px × 1.6 × 1 line each | 320px (5×64px) |
| 4 gaps between bullets: 24px each | 96px |
| **Total** | **816px ✅ fits in 840** |

**Page-level rules:**

- One heading + body OR one heading + ≤5 short bullets — not both a body paragraph *and* a long bullet list.
- A bullet must fit one line at the chosen size; if it wraps, shorten or move to its own page.
- Hero title pages (140–200px): title + 1 subtitle + maybe an eyebrow, nothing else.
- Section headings (80–120px): need almost nothing else on the page.
- If you're raising padding, shrinking type below scale, or tightening line-height under 1.4 to cram content in — **split into two pages instead**.

**Page count is a starting point, not a ceiling.** When the user gives a target count ("6 slides") but also hands you dense structured source material (e.g. a full agenda with N numbered sections, each with several sub-points), and N + cover/closing exceeds the target, prefer **matching the content's natural structure 1:1** (one page per numbered section) over cramming multiple sections onto one page. State the adjusted count and why when handing off — the user's own phrasing "N slides or adjust to fit" is implicit permission for this in most requests, but restate the assumption regardless.

**Never** use `overflow: auto/scroll`, negative margins, or transforms to hide overflow.

## Visual direction

Pick one coherent look, hold it every page:

- **Palette** — 1 background, 1 primary text, 1 accent, 1 muted. Constants at top of file.
- **Typography** — one display font + one body font. System stack unless user specifies. Heavy weight (800–900) headlines, normal (400–500) body.
- **Layout grid** — one content padding value, held throughout. Left-aligned = editorial; centered = ceremonial.
- **Aesthetic commitment** — choose ONE: minimal, maximalist, editorial, retro, brutalist, soft/pastel, neon, paper/print. Don't mix.

## Themes

If `themes/<id>.md` exists and the slide should follow it, the theme file **overrides these defaults** — palette, typography, layout padding, Title/Footer are authoritative. Read it first. `mode: dark`/`mode: light` in frontmatter sets the slide's background mode.

## Design system (opt-in, per-slide — default to using it)

```tsx
import type { DesignSystem, Page } from '@open-slide/core';

export const design: DesignSystem = {
  palette: { bg: '#f7f5f0', text: '#1a1814', accent: '#6d4cff' },
  fonts: {
    display: 'Georgia, "Times New Roman", serif',
    body: '-apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif',
  },
  typeScale: { hero: 168, body: 36 },
  radius: 12,
};
```

Must be `export` (not plain `const`) so the framework can read it and inject CSS vars at canvas root. Object initializer must be a literal — no spreads, no helper calls.

Two consumption surfaces, mix both in the same slide:

- **`var(--osd-X)`** for visual properties (color/font/font-size/radius) — instant live updates while dragging the Design panel slider. Vars: `--osd-bg`, `--osd-text`, `--osd-accent`, `--osd-font-display`, `--osd-font-body`, `--osd-size-hero`, `--osd-size-body`, `--osd-radius`.
- **Direct `design.X` reads** — for JS arithmetic or UI labels; updates via HMR after the panel commits the file.

Default to declaring `design` on every new slide so it's tweakable from the panel. Only skip it for a one-off slide with an intentionally locked palette (fall back to local `palette` constants).

## Starter template

```tsx
import type { DesignSystem, Page, SlideMeta } from '@open-slide/core';

export const design: DesignSystem = {
  palette: { bg: '#0f172a', text: '#f8fafc', accent: '#fbbf24' },
  fonts: {
    display: 'system-ui, -apple-system, sans-serif',
    body: 'system-ui, -apple-system, sans-serif',
  },
  typeScale: { hero: 180, body: 40 },
  radius: 12,
};

const muted = '#94a3b8';
const fill = { width: '100%', height: '100%', fontFamily: 'var(--osd-font-body)' } as const;

const Cover: Page = () => (
  <div style={{ ...fill, background: 'var(--osd-bg)', color: 'var(--osd-text)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 160px' }}>
    <div style={{ fontSize: 28, color: 'var(--osd-accent)', letterSpacing: '0.2em' }}>CHAPTER 01</div>
    <h1 style={{ fontFamily: 'var(--osd-font-display)', fontSize: 'var(--osd-size-hero)', fontWeight: 900, margin: '32px 0', lineHeight: 1.05 }}>
      The Big Idea
    </h1>
    <p style={{ fontSize: 'var(--osd-size-body)', color: muted, maxWidth: 1200 }}>
      A short subtitle that explains what this slide is about.
    </p>
  </div>
);

const Content: Page = () => (
  <div style={{ ...fill, background: 'var(--osd-bg)', color: 'var(--osd-text)', padding: 120 }}>
    <h2 style={{ fontFamily: 'var(--osd-font-display)', fontSize: 80, fontWeight: 800, margin: 0 }}>Section heading</h2>
    <ul style={{ fontSize: 'var(--osd-size-body)', lineHeight: 1.6, marginTop: 64, paddingLeft: 48 }}>
      <li>One clear point per line</li>
      <li>Keep to 3–5 bullets</li>
      <li>Let the space breathe</li>
    </ul>
  </div>
);

export const meta: SlideMeta = { title: 'The Big Idea', createdAt: '2026-05-16T12:00:00Z' };
export default [Cover, Content] satisfies Page[];
```

## Assets

Slide-local: `slides/<id>/assets/`, import as ES modules (`import hero from './assets/hero.jpg'`) or URL-only via `new URL('./assets/intro.mp4', import.meta.url).href`. Global (logos, recurring icons): project-root `assets/`, import via `@assets/logos/acme.svg`. Skip `assets/` entirely for pure-text slides.

## Image placeholders

```tsx
import { ImagePlaceholder } from '@open-slide/core';
<ImagePlaceholder hint="Product hero screenshot" width={1280} height={720} />
```

Use only when a specific concrete image the user must supply is genuinely required (product screenshot, team photo, customer dashboard). Never for decoration, generic stock-photo filler, or anything typography/layout could carry instead. `hint` describes content ("Q3 revenue chart"), not role ("hero image").

**Decorative/illustrative visuals** ("add images as seasoning/related objects", icons, diagrams) are a typography/SVG problem, not an asset problem — write small custom inline SVG components (one per motif, reusing the deck's accent/tint colors and hairline-border style), not `<ImagePlaceholder>` and not an icon library import.

## Page numbers

Never hardcode `n`/`TOTAL`. Read from the hook, called inside a per-page component:

```tsx
import { useSlidePageNumber } from '@open-slide/core';
const Footer = () => {
  const { current, total } = useSlidePageNumber();
  return <span>{String(current).padStart(2, '0')} / {String(total).padStart(2, '0')}</span>;
};
```

## Stepped reveals (`<Steps>` / `<Step>`)

Wrap deferred parts in `<Step>`, wrap the group in `<Steps>`. Each → reveals the next Step; → after the last advances page. ← peels back.

- `<Step>` must be a *direct* child of `<Steps>` — nested deeper or parentless renders fully revealed, defers nothing.
- Non-`Step` children render immediately (headline-always, body-in-turn pattern).
- Multiple `<Steps>` blocks on one page compose in document order (first finishes before second begins).
- Entering forward starts empty and builds; jumping via overview grid or arriving backward shows the page fully composed. Design pages to read well both ways.
- `<Step duration={...}>` (default 180ms) fades in; `prefers-reduced-motion: reduce` auto-collapses to an instant cut.
- Use when *order* is the point (build-up, before/after, payoff-last list). Don't wrap glance-and-get-it content (hero title, single quote, diagram) — those are stronger shown whole.

## Page transitions

No default — pages snap unless a `SlideTransition` is declared. Snap-swap is tasteful; only opt in when motion adds something. `prefers-reduced-motion: reduce` is auto-honored.

Incoming page wins: A→B uses `pages[B].transition ?? module.transition`; its `exit` plays on A, `enter` on B.

```tsx
import type { Page, SlideTransition } from '@open-slide/core';
export const transition: SlideTransition = { /* module default */ };
Cover.transition = { /* per-page override */ };
```

```ts
type TransitionPhase = { keyframes: Keyframe[] | PropertyIndexedKeyframes; duration?: number; easing?: string; delay?: number };
type SlideTransition = { duration: number; easing?: string; enter?: TransitionPhase; exit?: TransitionPhase };
```

`--osd-dir` (1 forward / -1 backward) + `data-osd-dir` on the wrapper let one keyframe mirror direction without JS.

**Design principles**: one DNA across the whole deck (same duration band, easing pair, out-then-in stagger — vary only *which property* nudges: Y/X/opacity/scale/blur). Duration 140–280ms (exit 140–180, enter 200–280, enter delayed ~80ms to overlap). Magnitude ceiling 12px / 3% scale. Opacity always part of it. Ease-in for exit (`cubic-bezier(0.4,0,1,1)`), ease-out for enter (`cubic-bezier(0,0,0.2,1)`). Never `linear`.

**Tasteful family** (pick one as house transition, optionally a second for cover, a third for section breaks):

```tsx
const EASE_OUT = 'cubic-bezier(0, 0, 0.2, 1)';
const EASE_IN  = 'cubic-bezier(0.4, 0, 1, 1)';

// RISE — house quiet, 6px Y. Module default.
export const transition: SlideTransition = {
  duration: 200,
  exit:  { duration: 140, easing: EASE_IN,  keyframes: [{ opacity: 1, transform: 'translateY(0)' }, { opacity: 0, transform: 'translateY(-4px)' }] },
  enter: { duration: 200, delay: 80, easing: EASE_OUT, keyframes: [{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'translateY(0)' }] },
};

// DISSOLVE — pure opacity, quietest possible.
const dissolve: SlideTransition = {
  duration: 240,
  exit:  { duration: 200, easing: EASE_IN,  keyframes: [{ opacity: 1 }, { opacity: 0 }] },
  enter: { duration: 240, delay: 40, easing: EASE_OUT, keyframes: [{ opacity: 0 }, { opacity: 1 }] },
};

// SETTLE — cover-grade: rise + a hair of blur on enter only.
Cover.transition = {
  duration: 280,
  exit:  { duration: 160, easing: EASE_IN,  keyframes: [{ opacity: 1, transform: 'translateY(0)' }, { opacity: 0, transform: 'translateY(-6px)' }] },
  enter: { duration: 280, delay: 100, easing: EASE_OUT, keyframes: [{ opacity: 0, transform: 'translateY(12px)', filter: 'blur(4px)' }, { opacity: 1, transform: 'translateY(0)', filter: 'blur(0)' }] },
};

// BLOOM — scale 0.97→1, no translate. Materializes in place.
const bloom: SlideTransition = {
  duration: 240,
  exit:  { duration: 160, easing: EASE_IN,  keyframes: [{ opacity: 1, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(1.01)' }] },
  enter: { duration: 240, delay: 80, easing: EASE_OUT, keyframes: [{ opacity: 0, transform: 'scale(0.97)' }, { opacity: 1, transform: 'scale(1)' }] },
};

// FALL — mirrored Rise, incoming page comes down from above.
const fall: SlideTransition = {
  duration: 200,
  exit:  { duration: 140, easing: EASE_IN,  keyframes: [{ opacity: 1, transform: 'translateY(0)' }, { opacity: 0, transform: 'translateY(4px)' }] },
  enter: { duration: 200, delay: 80, easing: EASE_OUT, keyframes: [{ opacity: 0, transform: 'translateY(-6px)' }, { opacity: 1, transform: 'translateY(0)' }] },
};

// BREATH — section break only, exit fully, hold 120ms, then enter. Use at most 1-2x per deck.
const breath: SlideTransition = {
  duration: 460,
  exit:  { duration: 180, easing: EASE_IN,  keyframes: [{ opacity: 1 }, { opacity: 0 }] },
  enter: { duration: 240, delay: 300, easing: EASE_OUT, keyframes: [{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'translateY(0)' }] },
};
```

Direction-aware keyframes (sparingly): `transform: 'translateX(calc(var(--osd-dir, 1) * 8px))'` → `translateX(0)`. If reaching for this on every transition, you're over-designing.

**Anti-patterns**: 6 different transitions in one deck; `translateX(100%)` slide-from-side (PowerPoint Push); scale-pop 0.85→1 + blur (lightbox vocabulary); `clip-path: inset()` reveals (After Effects); parallel blur both layers; duration >350ms; translate >12px or scale >3%; `linear` easing; declaring a transition without a clear reason (omit — snap-swap is fine).

## Repeated elements: component, not `map`

Visually repeated items (cards, logo rows, gallery tiles, step indicators) → define a small component **inside the same `index.tsx`**, instantiate it once per item explicitly. Never `array.map` over a data array for these — the inspector edits source JSX in place, and a `map` body is one shared source location that mutates every rendered instance together.

```tsx
// ✅ each card its own JSX node
const Card = ({ src, label }: { src: string; label: string }) => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
    <img src={src} style={{ width: 320, height: 320, objectFit: 'cover', borderRadius: 12 }} />
    <p style={{ fontSize: 32 }}>{label}</p>
  </div>
);
<div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 64 }}>
  <Card src={alpha} label="Alpha" />
  <Card src={beta} label="Beta" />
  <Card src={gamma} label="Gamma" />
</div>
```

Pure-text lists (`<ul><li>` bullets) are fine as plain literal markup — each `<li>` is already its own JSX node. One-off SVG icon components used exactly once each (e.g. a different illustrative motif per page) are still worth extracting to a named component even without repetition — it keeps each page's JSX readable and gives the icon a stable, referenceable name; this doesn't conflict with any "no tiny functions" lint concern since the component body is real multi-line markup, not a pure pass-through rename.

## Runtime behavior (free)

Home page lists every folder under `slides/`. Clicking a slide shows thumbnail rail + main page + prev/next + counter. Arrow keys/PageUp/PageDown navigate; `F` fullscreen play mode (Space/→ next, ← prev, Esc exit). Hot reload on save.

## QA-ing a slide in the real browser (do this, don't eyeball the code)

The dev server actually renders your page — use it as ground truth rather than reasoning about CSS in your head.

- **Navigate by URL query, not thumbnail clicks.** `http://0.0.0.0:5173/s/<id>?p=<pageNumber>` is reliable. Clicking thumbnail rail entries (`tab.click('text/03')`) can time out if the target page's thumbnail is scrolled out of the rail's visible area — this gets worse as page count grows past ~6.
- **Wait past entrance animations before measuring.** If pages use `fadeUp`/`fadeIn` entrance animations, a check taken immediately after navigation catches mid-animation transform/opacity values (e.g. an element still at `translateY(16px)`), which reads as a false-positive layout bug. Wait at least the animation's total duration + delay (typically 1.0–1.5s covers everything) before measuring geometry.
- **Overflow checks must be canvas-relative, not viewport-relative.** The dev UI renders multiple copies of a page simultaneously (main viewer, thumbnail rail, possibly an overview grid or PDF-export root), each at a different on-screen scale and position. Don't compare `getBoundingClientRect()` values across different snippets of code without normalizing to the same canvas instance in the same call. Correct pattern (single `tab.evaluate`):
  ```js
  const candidates = Array.from(document.querySelectorAll('div')).filter(el => el.offsetWidth === 1920 && el.offsetHeight === 1080);
  let best = null, bestArea = 0;
  for (const el of candidates) {
    const r = el.getBoundingClientRect();
    const area = r.width * r.height;
    if (area > bestArea) { bestArea = area; best = el; } // largest on-screen instance = the main viewer, not a thumbnail
  }
  const canvasRect = best.getBoundingClientRect();
  const scale = canvasRect.width / 1920;
  // for any descendant: nativeOverflow = (descendantRect.bottom - canvasRect.bottom) / scale
  ```
- **Exclude decorative glow/gradient elements from overflow findings.** A `radial-gradient` halo intentionally positioned off-center (`left: 80%`, `marginLeft: -320`, etc.) will legitimately extend past the canvas edge — that's the design, harmlessly clipped by the page root's `overflow: hidden`. Filter these out (`getComputedStyle(el).backgroundImage.includes('radial-gradient')`) before treating a positive `rightOver`/`bottomOver` number as a real bug, or you'll chase phantom overflow that's actually just the halo bleeding off-canvas by design.
- **When searching for a specific element by text content**, `querySelectorAll('*').filter(el => el.textContent.includes(needle))` returns every ancestor up the tree too (each contains the descendant's text), not just the actual target — their bounding rects will be nonsensical (e.g. spanning the whole page). Pick the smallest-area match, or query a specific tag/leaf, not the first match in document order.
- **After confirming zero overflow**, screenshot each page with a normalized selector (tag the resolved "main viewer" element with a temp `data-qa-canvas` attribute, screenshot by that selector) for a final visual pass — text density, icon legibility, color balance.

## Self-review before finishing

- [ ] `export default`s a non-empty `Page[]`.
- [ ] Every page root fills 100%×100%.
- [ ] Content lives inside padding, nothing touches the edge.
- [ ] **Every page: sum (font_size × line_height × lines) + gaps + 2×padding ≤ 1080px.** Split if close. No `overflow: auto`.
- [ ] No bullet wraps to a second line at chosen size.
- [ ] One coherent visual direction (palette + type scale) across every page.
- [ ] Declares top-level `export const design: DesignSystem` and uses `var(--osd-X)` (unless intentionally locked one-off).
- [ ] One idea per page.
- [ ] Repeated visual elements are explicit `<Component />` instances, not `array.map`.
- [ ] All imported assets exist on disk.
- [ ] Every `<ImagePlaceholder>` is for content the user must supply — not decorative filler.
- [ ] `<Steps>`/`<Step>` pages read complete when jumped to via overview grid.
- [ ] Any `SlideTransition` sits in one family (duration 140–280ms, same easing pair, magnitude <12px/3%). No six-vocabulary decks.
- [ ] Nothing outside `slides/<id>/` was edited.
- [ ] `pnpm exec tsc --noEmit` from the project root is clean.
- [ ] Verified live in the dev server per the QA section above — zero real overflow (canvas-relative, glow-excluded, post-animation), screenshots checked page by page.

## Anti-patterns

Walls of text (>~40 words → split). Full-canvas body copy (respect 100–160px padding). Overflowing 1080px vertically. `overflow: auto/scroll/hidden` to hide too much content. Type below scale lower bound or padding below 100px to cram in. Bullets wrapping to a second line. Body type under 28px (unreadable on a projector). Inconsistent palette across pages. Installing packages. CSS in a shared file (inline/scoped only). `README.md` inside a slide folder. Editing `package.json`/`open-slide.config.ts`/other slides. `<ImagePlaceholder>` sprinkled "for visual interest" or used for icons/decorative shapes. `array.map` for visually repeated elements. Wrapping every page in `<Step>` reflexively. `<Step>` not a direct child of `<Steps>`. Trusting a code-reading-only review instead of actually loading the page in the dev server. Measuring overflow with viewport-relative coordinates instead of canvas-relative. Copying a rich reference slide's full motion inventory when the user asked for subtle/restrained motion.
