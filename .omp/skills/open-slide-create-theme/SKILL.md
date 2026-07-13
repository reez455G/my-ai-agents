---
name: open-slide-create-theme
description: "Use when the user wants to create, draft, author, or extract a reusable slide theme in the live open-slide app at ~/opt_data/open-slide/apps/demo. Triggers on \"create a theme\", \"make a theme called X\", \"extract a theme from slide\", \"build a theme from these images\". Produces a paired themes/id.md + themes/id.demo.tsx bundle. Do NOT use for editing real slides."
---

## Workspace

Project root: `/home/efsatu/opt_data/open-slide/apps/demo`. You only write `themes/<id>.md` and `themes/<id>.demo.tsx`. Never modify real slides or config. Canvas/type-scale defaults that themes can override live in **`open-slide-slide-authoring`** — read it first so overrides are stated explicitly.

## What a theme is

Two paired files sharing a stem:

1. `themes/<id>.md` — agent-facing docs: palette, typography, layout, fixed Title/Footer/Eyebrow components, motion. `open-slide-create-slide` reads this when an author picks the theme.
2. `themes/<id>.demo.tsx` — a runnable mini-slide (`export default Page[]`) demonstrating the theme on 2–3 pages. The dev UI's **Themes panel** loads and renders it live.

Distinct from a slide's `design` const: the markdown is authoring-time direction (copied into a real slide by `open-slide-create-slide`); the demo `.tsx` is a self-contained preview (not a real slide, doesn't appear in the slides list); a per-slide `design` const is the runtime-tweakable tokens object. Markdown commits the *direction*, `design` const makes a slide *tweakable*, demo `.tsx` makes the theme *previewable*.

## Step 1 — Identify input source

Three possible shapes: image references (screenshots, mood boards, brand assets), free-text description, or an existing slide (`slides/<id>/index.tsx` to lift a visual identity out of). If ambiguous, ask (multi-select) which source(s), then follow-ups (paths/slide id/prose) as needed.

## Step 2 — Gather raw inputs

- **Images**: read each (image-capable read). Note dominant hex colors, type weight/style, layout rhythm, motifs, recurring chrome.
- **Text**: extract explicit tokens (hex, font names, motion verbs) and implicit tone words; resolve vague language into concrete decisions.
- **Existing slide**: read it and pull the `palette` object → Palette; font constants/font-size patterns → Typography; padding/alignment → Layout; recurring components (TrafficLights, Eyebrow, Footer helpers, WindowShell…) → Fixed components; `@keyframes` blocks/shared styles → Motion; overall feel → Aesthetic paragraph.

If inputs disagree (images say blue, description says green), ask which to honor.

## Step 3 — Pick a theme id

Kebab-case, short, descriptive (`editorial-noir`, `brutalist-mono`, `pastel-soft`, `dev-terminal`). Check `themes/` to avoid collisions.

## Step 4 — Write `themes/<id>.md`

Fixed section order (bodies adapt, headings stay consistent):

````markdown
---
name: <Human title>
description: <one-line elevator pitch>
---

# <Theme name>

## Palette

| Role | Value | Notes |
|---|---|---|
| bg | `#0f172a` | page background |
| text | `#f8fafc` | primary copy |
| accent | `#fbbf24` | callouts, eyebrow, key numbers |
| muted | `#94a3b8` | secondary copy, dividers |
| ... | ... | extend as needed |

## Typography

- Display font: `<stack>` — weight 800–900 headlines.
- Body font: `<stack>` — weight 400–500.
- Type-scale overrides (only what differs from `open-slide-slide-authoring` defaults).

## Layout

- Content padding: `<N>`px from canvas edges (1920×1080).
- Alignment, grid notes.

## Fixed components

Paste-ready — copy verbatim into a slide using this theme.

### Title
```tsx
const Title = ({ children }: { children: React.ReactNode }) => (
  <h1 style={{ fontSize: 140, fontWeight: 900, lineHeight: 1.05, letterSpacing: '-0.02em', margin: 0, color: '#f8fafc' }}>
    {children}
  </h1>
);
```

### Footer

Pull page number from `useSlidePageNumber()` — never hardcode.

```tsx
import { useSlidePageNumber } from '@open-slide/core';
const Footer = () => {
  const { current, total } = useSlidePageNumber();
  return (
    <div style={{ position: 'absolute', left: 120, right: 120, bottom: 60, display: 'flex', justifyContent: 'space-between', fontSize: 24, color: '#94a3b8' }}>
      <span>THEME NAME · 2026</span>
      <span>{current} / {total}</span>
    </div>
  );
};
```

### Eyebrow / accents (optional)
```tsx
const Eyebrow = ({ children }: { children: React.ReactNode }) => (
  <div style={{ fontSize: 26, letterSpacing: '0.2em', color: '#fbbf24' }}>{children}</div>
);
```

## Motion

- Philosophy: static / subtle / rich — one sentence.
- Reusable keyframes (only if subtle/rich).

## Aesthetic

One paragraph: what it feels like, references, what to avoid. Commit to one direction — minimal, maximalist, editorial, retro, brutalist, soft/pastel, neon, paper/print.

## Example usage

A runnable Cover snippet using the components above.
````

## Step 4b — Write `themes/<id>.demo.tsx`

Same shape as a real slide module, sits under `themes/` (preview-only). The dev UI's Themes panel imports it and renders it in `SlideCanvas` (1920×1080).

Contract:
- `import { type Page, useSlidePageNumber } from '@open-slide/core';`
- Inline the **same** Title/Footer/Eyebrow defined in the markdown — verbatim, no abstractions, no external imports. Demo and markdown must stay in lockstep.
- Export 2–3 `Page`s + default array: a Cover (Eyebrow+Title+subtitle), one Content page exercising body type + accent, a Closer/"End" card.
- If the theme has runtime-tweakable tokens, also `export const design: DesignSystem = {...}`.
- No external assets, no `@/` imports, no slide-only helpers. Self-contained.

## Step 5 — Self-review

- [ ] Palette covers bg/text/accent/muted at minimum, all hex.
- [ ] Type scale: hero/heading/body/caption sizes (or explicitly defers to slide-authoring defaults).
- [ ] Title and Footer are paste-ready React with concrete inline styles.
- [ ] Motion section commits to static/subtle/rich.
- [ ] Aesthetic paragraph names one coherent direction.
- [ ] Both files written; no slide/config changes.
- [ ] Demo exports 2–3 pages, inlines the same Title/Footer/Eyebrow as the markdown.
- [ ] Demo opens cleanly in the Themes panel — verify by reading the file, don't start a server.

## Step 6 — Hand off

Tell the user: theme id + both file paths; the demo appears live in the dev UI's Themes panel (HMR, no restart); `open-slide-create-slide` will list it as a picker option next run; one-line look summary (palette + aesthetic). Don't run the dev server. Don't touch real slides — the demo `.tsx` is the demonstration.

## Anti-patterns

Executable code in `themes/<id>.md` outside labeled snippets. Markdown-only or demo-only (theme is always the bundle). Treating the demo as a real slide (never under `slides/`). Importing from `@/` or slide-specific helpers in the demo. Inventing palette/fonts when the user supplied images/an existing slide — extract, don't fabricate. Editing `slides/`, `packages/`, `package.json`, `open-slide.config.ts`. Skipping the Fixed components section.
