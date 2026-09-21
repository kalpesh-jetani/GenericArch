# Navigation & Routes

Every route the app defines, what renders it, and how it is reached. An index — grep a row, then
open the code it points at.

**Read it when** you need to find where a route is declared or rendered, or how a deep link
resolves — before grepping the tree.

---

## Route inventory

Filled by `/sync-app-notes` from the project. Columns follow the active profile; the shape below is
the common one. Blank until a profile is declared.

| Route | Payload | Defined in — *what's there* | Rendered by — *what's there* | Entry points | Deep link |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

---

## Deep links

| URL pattern | Parses to | Parser — *what's there* | Requires auth | Fallback if unauthorized |
|---|---|---|---|---|
| — | — | — | — | — |

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags a route nothing renders, a deep link that parses to no route, and a
route defined but never entered.
