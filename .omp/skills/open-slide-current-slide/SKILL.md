---
name: open-slide-current-slide
description: "Resolve which slide/page/element the user is currently viewing in the open-slide dev server at ~/opt_data/open-slide/apps/demo (0.0.0.0:5173). Consult whenever the user references \"this page\", \"this slide\", \"this element\", \"the slide I'm on\", \"the current page\", or any deictic reference to slide content without naming it. Re-read the cursor file at the start of every such turn — it goes stale the moment the user navigates."
---

## Workspace

Project root: `/home/efsatu/opt_data/open-slide/apps/demo`.

When the user says "fix this page", "tweak this heading", or "the slide I'm looking at", they almost never name the slide id, page number, or element — they mean wherever they are in the dev viewer. Before asking "which slide?"/"which element?", check the file the dev server writes on every navigation and inspector pick.

## Re-read on every deictic turn — never reuse a prior read

`current.json` is a live cursor, not a conversation fact. The user moves between slides/pages/elements freely between turns — including while you were doing other work. **Read fresh at the start of every new turn using a deictic reference**, even if you already read it earlier in this conversation, just finished editing the slide it pointed to, or the message sounds like a continuation ("now make it bigger", "also fix this one", "keep going"). "Continue editing" is exactly the case where the user likely just navigated elsewhere — trusting a stale read silently edits the wrong file. Re-read, compare `slideId`/`pageIndex`/`selection` against last time, act on the new values.

## How to read it

```
node_modules/.open-slide/current.json
```

Path is relative to the project root (`/home/efsatu/opt_data/open-slide/apps/demo` — the directory with `slides/` and `package.json`). Plain JSON file.

## What you get

```json
{
  "slideId": "q2-roadmap",
  "pageIndex": 2,
  "pageNumber": 3,
  "totalPages": 8,
  "slideTitle": "Q2 Roadmap",
  "view": "slides",
  "pagePath": "slides/q2-roadmap/index.tsx",
  "selection": {
    "line": 42,
    "column": 6,
    "tagName": "h1",
    "text": "Q2 Roadmap"
  },
  "updatedAt": "2026-05-09T14:32:11.123Z"
}
```

- `slideId` — folder name under `slides/`. Use as-is for `/__slides/<id>/...` APIs or the URL segment.
- `pageIndex` — 0-based, for the page array in `index.tsx` (`export default [Cover, Body, ...]`).
- `pageNumber` — 1-based, for user-facing messages ("page 3 of 8") and URL `?p=N`.
- `pagePath` — relative path to slide source; read/edit it directly.
- `view` — `"slides"` (canvas view) or `"assets"` (user is browsing that slide's files, not viewing a page).
- `selection` — `null` if nothing selected. Otherwise the JSX element picked in the inspector overlay: `line` (1-indexed)/`column` (0-indexed) point to the JSX opening tag inside `pagePath` — the canonical handle, match against source line not rendered DOM. `tagName` is the lowercased rendered DOM tag. `text` is a trimmed ≤120-char textContent snippet, a sanity check you're on the right node. Selection auto-clears on navigation to a different slide/page.
- `updatedAt` — ISO timestamp of last navigation/selection change; use to detect staleness.

## When to use this

User references the current slide/page deictically ("this", "here", "the page I'm on"), or a specific element ("this heading", "this image", "the button I just clicked" — if `selection` is non-null, that's the element). Before asking "which slide?"/"which element?". Before guessing from `git log`, recently-edited files, or the newest slide folder.

## When NOT to use this

User names a slide explicitly ("edit `q2-roadmap`") — use that name directly. The `open-slide-apply-comments` workflow already locates the right file via `@slide-comment` markers — doesn't need this. For listing/discovering slides — read `slides/` directly.

## Staleness — verify before acting

- **Fresh (under ~5 min old)**: trust it, open `pagePath`, do the work.
- **Older than ~5 min, or older than your last interaction with the user**: confirm with the user before editing — the dev server may not be running, or the user switched contexts.
- **Hours/days old**: ignore it, ask the user which slide they mean.

A *newer* `updatedAt` than what you saw last turn is the normal signal the user moved — switch to the new `slideId`/`pageIndex`/`selection` without asking.

## When the file is missing

Dev server hasn't been opened on a slide yet, or has never run. Don't create the file or guess — ask the user which slide they mean, or suggest opening it in the dev server first.

## Example — page-level reference

User: "tighten the spacing on this page"
1. Read `node_modules/.open-slide/current.json`.
2. Check `updatedAt` is recent.
3. Read `pagePath` (e.g. `slides/q2-roadmap/index.tsx`).
4. Identify the page at `pageIndex` in the default-exported array.
5. Consult `open-slide-slide-authoring` for spacing rules, edit that page in place.

If missing/stale: ask "Which slide and page should I tighten? The dev server hasn't published a current page recently."

## Example — element-level reference

User: "make this bigger"
1. Read `current.json`.
2. If `selection` is non-null, that's the element — read `pagePath`, jump to `selection.line`, find the JSX opening tag near that line/column, confirm via `selection.text`/`tagName`.
3. Consult `open-slide-slide-authoring` for type-scale/layout rules before editing.
4. Edit the JSX node in place.

If `selection` is null, fall back to the page-level flow — consider asking "which element?" since the user used a deictic but hasn't picked one in the inspector.
