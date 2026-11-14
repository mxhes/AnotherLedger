# Footer as a value table: design (2026-11-15)

## Why

Mid-farm the player looks at two things: the **best value** and **how fast it
comes in (gold per hour)**. The current footer is three stacked blocks (Items,
Raw gold, Items + gold; 158 px) that bury those two numbers under the vendor /
AH split and take rows away from the list.

## Goals

- A compact table: rows **Items / Raw gold / Total**, columns **Value** (best)
  and **/h**.
- The freed height goes to the list.
- Nothing visible today is lost: it is either in the table or in the hover
  tooltip.

## Non-goals

- No change to the `View` totals, the data broker or the History data.

## Approaches

- **A. Headline + one detail line, rest on hover** (~40 px). Most compact.
- **B. Small table** (~72 px). **Picked**: shows the item rate against the raw
  gold rate at a glance.
- **C. The three blocks slimmed to one line each** (~90 px). Rejected: least
  gain, keeps the stacked-block look.

## Design

```
           Value        /h
Items    1,000g      330g
Raw gold   234g       82g
Total    1,234g      412g
filtered · 3 unpriced
```

- Label left; the Value column right-aligned; the /h column at the right edge.
  A rate shows an em dash while there is none (as today).
- Font: the existing 12 pt summary font. The **Total** row is gold; the column
  titles use the hint color (small font).
- **Notes line** (small, one line, below the table), shown only when there is
  something to say: `filtered`, `N unpriced` (stale orange) and the bank
  scan-age note, joined with ` · `. Without notes it takes no space. The line
  is orange when any part is orange-worthy (unpriced, filtered, stale scan);
  otherwise ink.
- **Bags / Bank** (`view.kind == "inventory"`): only the Items row, no /h column
  and no column titles.
- **History**: same as Session.
- **Option "Include raw gold" off** (`view.noCombined`): the Total row is
  dropped.
- **Tooltip**: hovering the table shows vendor / AH / best with their rates,
  for items and for items + gold (rates and the gold part only where the view
  has them).
- **Sizes**: rows 18 px; header + 3 rows = 72 px (90 px with the notes line),
  down from 158. `minHeight` drops from 514 to about 428 (recomputed by the
  tests). `minWidth` 350 stays: worst case (German "Gegenstände" +
  `123456g 78s 90c` + `999g 59s 59c/h`) is about 280 px of 326.
- **Code**: replace the block / pair / label code in `UI/Summary.lua` and the
  `footer*` sizes in `Theme.lua`. A pure `Summary.tableLayout(view)` gives the
  visible rows, whether the /h column and titles show, and the height; the
  tests cover it. Top finds stays as it is, below the footer.
- README footer text and in-client checklist updated; German texts for the new
  strings ("Total", "/h" column title if not already a key).

## Left to the builder

Exact column padding; the tooltip anchor.
