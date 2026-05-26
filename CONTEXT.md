# Fresh Pantry — Domain Context

A self-use household pantry app: tracks fridge/pantry stock, signals expiry, suggests recipes from current stock, and turns **Proposals** (from pastes, cooking, shopping) into reviewed updates to Inventory.

## Language

**Ingredient**:
One row in inventory; identity = `name × unit × Storage Area × (Batch for Perishables)`.
_Avoid_: using "ingredient" for recipe-required food — say "recipe ingredient" or "required food".

**Batch**:
A per-intake identity component for **Perishables** — every intake creates a new row carrying its own expiry, even if another row with the same name already exists.

**Perishable**:
A category attribute (meat, dairy, fresh produce, eggs, …). Opposite is **Non-perishable** (rice, oil, sauce, canned goods, …).

**Intake**:
A stock-addition operation — creates a new Ingredient row OR merges quantity into an existing one (depending on Perishable / unit / storage match).
_Avoid_: "add", "create" — too generic.

**Deduction**:
A stock-reduction operation — reduces qty on existing Ingredient row(s).
_Avoid_: "consume", "use up" — those are user-facing labels, not the operation.

**Proposal**:
A pending, system-suggested **Intake** / **Deduction** / merge awaiting user confirmation. Sources: paste-import (AI), recipe-completion, shopping-completion.
_Avoid_: "draft" — that's the code-level data type (`IngredientDraft`); **Proposal** is the conceptual unit being reviewed.

**Review**:
The shared confirmation step where the user inspects, edits, or rejects a list of **Proposals** before they apply atomically to Inventory.

**Urgency Status**:
Computed view of an Ingredient: `fresh / soon / urgent / expired / low-stock`. Drives color, badge, and any push.

**Storage Area**:
Physical location — `fridge`, `freezer`, `pantry`, etc. (see `StorageArea` enum). Same name in different areas = different Ingredient rows.

## Relationships

- An **Ingredient** has one **Storage Area** and, if **Perishable**, one **Batch**.
- A **Proposal** is either an **Intake** (new row or merge) or a **Deduction** (against existing row(s)).
- A **Review** session applies a list of **Proposals** atomically to Inventory.
- A **Recipe** references food by name + qty (no direct link to **Ingredient**); recipe completion fuzzy-matches names against current inventory to generate **Deduction** **Proposals**.

## Example dialogue

> **Dev:** "User pastes `牛奶 1 盒`, inventory already has `牛奶 1 盒 (剩 2 天)` — merge?"
> **You:** "牛奶 is **Perishable**. Default = new **Batch**. The **Review** shows the action and the user can override to merge."

> **Dev:** "And `米 5kg` + existing `米 3kg`?"
> **You:** "Non-perishable, same unit/storage → default merge: `米 8kg`."

## Flagged ambiguities

- "ingredient" — both inventory rows AND recipe-required food. Resolved: **Ingredient** = inventory row only; recipes use "recipe ingredient" / "required food".
- "draft" — used loosely. Resolved: code-level data type (`IngredientDraft`, `RecipeDraft`) vs **Proposal** as the conceptual unit being reviewed.
- "粘性 / stickiness" — used at project start to mean "feature richness". Resolved: this is a **self-use** app (A-mode); the real goal is "low-friction utility for the maintainer", not user retention. Avoid "粘性" in design discussions.
