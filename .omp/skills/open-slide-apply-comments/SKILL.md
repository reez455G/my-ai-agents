---
name: open-slide-apply-comments
description: "Apply pending @slide-comment inspector markers in the live open-slide app at ~/opt_data/open-slide/apps/demo. Use when the user asks to \"apply comments\", \"process slide comments\", \"apply the inspector comments\", or references markers left inside that project's slides/id/index.tsx."
---

## Workspace

Project root: `/home/efsatu/opt_data/open-slide/apps/demo`.

The open-slide editor's inspector lets a user click a rendered page element and attach a comment (e.g. "make this red", "change to 'Open Slide Rocks'"). Each is persisted as an in-source JSX marker inside `slides/<slideId>/index.tsx`. Job: read markers, perform the described edits, delete the markers.

**Before any page edit**, consult **`open-slide-slide-authoring`** — the technical reference for how `index.tsx` is structured (canvas, type scale, palette, assets, file contract). A comment like "make this bigger" or "change the accent colour" must be applied consistent with those rules.

## Marker format

```
{/* @slide-comment id="c-<8hex>" ts="<ISO>" text="<base64url(JSON)>" */}
```

- Sits on its own line as the **first child inside** the JSX element it refers to (between that element's opening `>` and its other children).
- `text` is base64url-encoded JSON: `{"note": "...", "hint"?: "..."}`.
- Detection regex (authoritative — use exactly this):
  ```
  /\{\/\*\s*@slide-comment\s+id="(c-[a-f0-9]+)"\s+ts="([^"]+)"\s+text="([A-Za-z0-9_\-]+={0,2})"\s*\*\/\}/g
  ```

## Procedure

1. **Identify target slide(s).** Named slide → work that single `slides/<slideId>/index.tsx`. "All" or unspecified → scan every `slides/*/index.tsx`, process one at a time.
2. **Find all markers.** Run the regex against the whole file. For each match, base64url-decode `text` and JSON-parse to `{ note, hint? }`. Record `{ id, lineIndex (0-based), indent, note, hint }`. No markers → tell the user and stop.
3. **Understand each comment in context.** The targeted JSX element is the **enclosing** element — read upward from the marker line to the unclosed JSX opening tag whose body it lives in. (Self-closing elements like `<img />`: the inspector hoists the marker to the nearest non-self-closing ancestor — the comment usually refers to a child, use `note` to disambiguate.) Read enough surrounding code (parent, siblings, inline styles) to apply faithfully. If `note` is ambiguous, do the smallest reasonable interpretation and mention the assumption in your summary.
4. **Apply edits in reverse line order.** Sort markers by descending `lineIndex`, process one at a time — top-down would invalidate later line numbers as the file shrinks/grows.
5. **Remove each marker after applying its edit.** Delete the entire marker line + trailing newline. Never leave a marker behind — an un-removed marker signals a failure.
6. **Verify.** Re-read the file, confirm zero remaining markers. Run `pnpm tsc --noEmit` and `pnpm biome check` (or `pnpm lint`) from the project root. Fix any introduced errors.
7. **Report.** `N applied, 0 remaining` + one-line description of each change (including slide id).

## base64url decoding helper

```js
function decode(s) {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/') + pad, 'base64').toString('utf8');
}
```
Run inline via `node -e '...'` to inspect a payload if needed; otherwise reason about the decoded string directly.

## Edge cases

- Marker with no enclosing JSX element (shouldn't happen, but if found): delete it, note as orphan.
- Multiple markers stacked on consecutive lines inside the same element: all refer to that element — apply in source order, delete each line individually.
- `_debugSource` used SWC instead of Babel: not relevant — the marker line is authoritative.
- Comment asks for something outside the target element's scope (e.g. "add a new page"): do the closest-reasonable edit, mention the scope expansion in your summary.
- Can't resolve the comment (truly ambiguous, or file shape changed so the target no longer exists): leave the marker in place, report as skipped. Don't guess.

## Do not

Touch `package.json`, `open-slide.config.ts`, or files outside `slides/`. Add dependencies. Re-introduce markers or leave `TODO` breadcrumbs.
