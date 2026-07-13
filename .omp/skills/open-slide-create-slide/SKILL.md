---
name: open-slide-create-slide
description: "Use when the user wants to create, draft, author, or generate new slides / a presentation in the live open-slide React app at ~/opt_data/open-slide/apps/demo (dev server on 0.0.0.0:5173). Triggers on \"make slides about X\", \"create a presentation\", \"draft slides for\", \"new slide/deck\", or adding content under that project's slides/. Owns the workflow (theme pick, scoping questions, page planning); delegates file-level technical rules to open-slide-slide-authoring. Do NOT use for editing the open-slide framework itself."
---

## Workspace

Project root: `/home/efsatu/opt_data/open-slide/apps/demo`. Verify it has `slides/`, `themes/`, `open-slide.config.ts` before working. Dev server: `http://0.0.0.0:5173`, started via `pnpm dev` from that directory (check `ss -ltnp | grep 5173` or the running process cwd if unsure whether it's already up).

This skill owns the **workflow** for drafting a new deck. The technical reference — file contract, 1920×1080 canvas, type scale, palette, layout, assets — lives in **`open-slide-slide-authoring`**. Read that skill whenever you need details on *how* a page is structured; don't duplicate that knowledge here.

You only write files under `slides/<id>/`. Never modify `package.json`, `open-slide.config.ts`, or existing slides.

## Step 1 — Pick a theme

List files under `themes/` (each real theme is a `<id>.md` + `<id>.demo.tsx` pair; ignore `README.md`). If any exist, ask the user (multi-option) with each theme id as an option plus a final **"no theme — design from scratch"** option.

- If picked: read `themes/<id>.md` end-to-end. Its palette, typography, layout, Title/Footer are now authoritative — copy them directly into the slide. **Set `theme: '<theme-id>'`** on the `meta` export in `index.tsx`. Skip the aesthetic-direction question in Step 2 (theme already commits to a direction) but still confirm the topic. Page count, density, motion stay independent questions.
- If "no theme" or `themes/` is empty/README-only: proceed to Step 2 unchanged.

If you skipped the aesthetic question because a theme was picked, restate the theme name in Step 2 so the user can correct course.

## Step 2 — Clarify requirements (before writing code)

Lock in four style decisions — they shape every downstream choice, so front-load them. **Only skip a question when the user's original message already gave an unambiguous answer** — if you skip, restate your assumption so they can correct it.

**Topic first.** If the request is thin ("make me a deck"), ask topic/audience/outline separately before the four below. Skip only if topic is already clear — restate your reading of it.

The four (single multi-question ask when needed):

1. **Aesthetic direction** — propose 3 visual directions tailored to *this* topic (not a fixed preset list). Each = vibe word + concrete visual cue (palette/typography/motif), so options feel meaningfully different. Mark the best-fit one "(Recommended)". Example shifts by topic:
   - "Intro to Rust for backend engineers" → rust-orange technical editorial (warm rust/charcoal, mono headings, code-grid) · blueprint dev-doc (cyan grid on near-black, monospace, schematic) · brutalist terminal (lime-on-black, ASCII rules)
   - "Q2 roadmap for stakeholders" → calm corporate clean (off-white, single accent, whitespace) · confident editorial (large display serif, tight grid, one bold accent) · data-forward dashboard (charts as hero, muted neutrals + status colors)
   - "Kindergarten parent night" → playful crayon (paper texture, hand-drawn accents, primary colors) · soft pastel storybook (peach/mint, rounded type, illustrated icons) · warm photo-led (full-bleed kid photos, simple captions)
2. **Page count** — brackets: 3–5 (short), 6–10 (standard), 11–20 (deep dive), custom.
3. **Text density per page** — minimal (one line/big number), light (heading + 2–3 bullets), standard (heading + 4–5 bullets or short paragraph), dense (multi-column/detailed). Drives type scale and layout.
4. **Motion** — static (none), subtle (fades/entrance only), rich (keyframes, staggered reveals, looping visuals). If animated: CSS `@keyframes` / inline `style` + `useEffect`, no extra libraries.

Ask follow-ups only if still unclear after these four (brand colors, required assets).

## Step 3 — Pick a slide id

Kebab-case, short, descriptive (`rust-intro`, `q2-roadmap`, `team-offsite-2026`). Check `slides/` to avoid collisions.

## Step 4 — Plan the structure

Sketch page roles before writing code:

| Role | Purpose |
|---|---|
| Cover | Title + subtitle, strong visual |
| Agenda | What's coming (3–5 items) |
| Section divider | Big label between chapters |
| Content | Heading + 2–5 bullets OR heading + one visual |
| Big number | One statistic the size of the canvas |
| Quote | Pull-quote with attribution |
| Comparison | Two-column before/after or A vs B |
| Closing | CTA, thanks, contact |

**Rule of thumb**: one idea per page — tempted to put two, split them.

If the deck needs real images the user must supply (screenshots, team photos, customer dashboards), plan the slot and use `<ImagePlaceholder>` from `@open-slide/core` (see open-slide-slide-authoring's "Image placeholders"). Default is no placeholders — only when a real image is genuinely required.

## Step 5 — Commit to a visual direction

One coherent palette/type-scale/aesthetic held across every page — full constraint set lives in `open-slide-slide-authoring`.

**Default: declare `export const design: DesignSystem = { … }`** at the top of `index.tsx`, reference values via `var(--osd-X)`. Keeps the slide tweakable from the Design panel post-generation. Only skip for a one-off slide with an intentionally locked, not-meant-to-be-retheme palette (fall back to local `palette` constants).

## Step 6 — Write `slides/<id>/index.tsx`

Read **`open-slide-slide-authoring`** first — file contract, canvas rules, type scale, spacing, asset imports, starter template. Don't duplicate that here.

## Step 7 — Self-review

Run the checklist in `open-slide-slide-authoring` ("Self-review before finishing") — structural correctness, layout discipline, asset existence.

## Step 8 — Hand off

Tell the user: the slide id + file path created; that the dev server hot-reloads, so open `http://0.0.0.0:5173/s/<id>` (or refresh the home page); if dev isn't running, `pnpm dev` from the project root. Don't start the dev server yourself unless asked.
