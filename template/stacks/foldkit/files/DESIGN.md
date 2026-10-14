# Design System — {{PROJECT_NAME}}

The starter's design system, as `src/styles.css` defines it: a small set of CSS custom properties
(tokens) on `:root`, used through classes. Views never set a colour, size or font inline. Change a
value here and in `src/styles.css` together, and QA holds the app to this file.

## Aesthetic
Plain and readable: one narrow column, system type, colour only where it carries meaning (a
status, the one action). A neutral starting point to replace with the project's own look.

## Color
Light only: there is no dark scheme yet. Adding one means a second value for every colour token
under `@media (prefers-color-scheme: dark)`, not new tokens. Each text colour from `--color-text`
to `--color-error` has at least 4.5:1 contrast on `--color-background`, and `--color-on-accent`
at least 4.5:1 on each accent (WCAG AA).

| Token | Value | Role |
|---|---|---|
| `--color-background` | `#ffffff` | the page background |
| `--color-text` | `#1f2328` | body text and headings |
| `--color-muted` | `#59636e` | secondary text (the version line) |
| `--color-ok` | `#1a7f37` | status `ok` |
| `--color-warning` | `#9a6700` | status `degraded` |
| `--color-error` | `#cf222e` | status `down` and failure messages |
| `--color-accent` | `#0969da` | buttons, and the focus outline on everything focusable |
| `--color-accent-hover` | `#0860ca` | a button under the pointer |
| `--color-accent-active` | `#0757ba` | a button being pressed |
| `--color-on-accent` | `#ffffff` | text on an accent background |

## Typography
`--font-sans`: `system-ui, -apple-system, 'Segoe UI', sans-serif`. The platform's own interface
face, on purpose: a neutral default that downloads nothing and reads well everywhere. When the
project picks a typeface, change this token. Sizes and weights are the browser's defaults (`h1`
for the title, body text for the rest); add size tokens before the first custom size.

## Spacing & layout
One scale, in steps of `0.25rem` (4px at the default 16px root size); use only these:

| Token | Value |
|---|---|
| `--space-1` | `0.25rem` |
| `--space-2` | `0.5rem` |
| `--space-4` | `1rem` |
| `--space-8` | `2rem` |

`--radius` (`0.375rem`) rounds every corner: buttons and focus outlines. `--size-target`
(`2.75rem`, 44px) is the smallest width and height of anything clickable. The page is a single
column at most `40rem` wide, centred, padded `--space-8` above and below and `--space-4` at the
sides.

## Motion
None: state changes are instant, with no transitions or animations. Anything added later must
honour `prefers-reduced-motion`.

## Anti-slop rules
- No literal colours, sizes or fonts in views or new rules: a token, through a class.
- Every interactive element has hover, active and `:focus-visible` states. Focus shows a 2px
  `--color-accent` outline offset 2px, and is never removed without a replacement.
- Nothing clickable is smaller than `--size-target`.
- Keyboard focus is never left on the page when the view changes: when the focused element
  goes away, a Command moves focus to one that stays (the status panel,
  `src/components/status.ts`).
