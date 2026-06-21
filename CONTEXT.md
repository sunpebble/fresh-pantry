# Fresh Pantry — Domain Context

A self-use household pantry app: tracks fridge/pantry stock, signals expiry, suggests recipes from current stock, and turns **Proposals** (from pastes, cooking, shopping) into reviewed updates to Inventory.

## Language

**Ingredient**:
One row in inventory; identity = `name × unit × Storage Area × (Batch for Perishables)`.
_Avoid_: using "ingredient" for recipe-required food — say "recipe ingredient" or "required food".

**Ingredient Identity** (`IngredientIdentity`):
The single module that owns the identity rule above — decides whether an **Intake** merges into an existing row or starts a new **Batch** (perishable, blank, unit/storage mismatch, or non-numeric target quantity → new row). Both the proposal-time default (`ProposalPlanner`) and apply-time re-resolution (`InventoryNotifier`) call through it, so the displayed default can never drift from what apply does. Implements ADR-0001.

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

## Sync vocabulary (infrastructure, not domain)

**Sync Finish** (the finishing sequence):
The ordered tail every local write runs *after* touching the outbox — one coalesced
**push**, a `pendingSyncRevision` **bump** (re-reads only the 待同步 badges; never the
heavier `dataRevision`, which is the remote-merge pulse that reloads every store), and
an optional cross-instance **refresh pulse** (so other *live store instances* reload).
Owned by one seam (`SyncWriter`) so that *"enqueue without finishing"* is
**unrepresentable** — the defect class behind `c0defc8` (missing pulse → stale list) and
`dabcbd4` (missing push+bump → stuck 「同步中,1 条待同步」). A **direct-outbox writer**
(the widget drainer, which enqueues in-process to keep Supabase out of the widget
extension) may bypass the *enqueue*, but must call the same **Sync Finish** entry —
it can skip a step only by not reaching the finish, which the seam forbids.
_Avoid_: re-deriving push/bump/pulse by hand in a new write path; bumping `dataRevision`
from a local write.

**CoordinatorPushing**:
The one-method seam (`pushPending()`) that `SyncCoordinator` conforms to, so **Sync
Finish** can be driven by a push-spy in tests — the structural gap whose absence let
both bugs ship past the suite.

**SyncableEntity**:
The protocol the seven synced models conform to (`id`, `remoteVersion`, `deletedAt`,
`hasSyncIdentity`, `withRemoteVersion`). It is what lets local⇄remote reconciliation be
written *once*: `HouseholdMergePolicy.merge`/`patch` and the apply sequence are generic
over it, so the soft-delete check and the local-only / well-formed predicates stop being
per-entity copies. `hasSyncIdentity` is each model's non-blank identity field
(`name` / `recipeId` / `keyword` / `recipeID`).

**Entity Plan** (`EntityPlan`):
One value per synced entity, holding its `SyncEntityType` plus the I/O bindings to its
local repository and the remote (load / save / remoteLoad / remoteUpsert / watch). The
coordinator holds `plans: [EntityPlan]` built in `init`; `startSync`, `refreshDelta`,
`subscribe`, `uploadLocalOnly`, and cursor-advance all **loop** over it. A generic
`plan<T: SyncableEntity>(…)` factory carries the decode→merge→save→signal sequence once,
so *adding an eighth synced entity is one `plan(…)` line* instead of edits across ~8
sites. This deepens `HouseholdContentSyncCoordinator` — a verbatim Dart port that
repeated the sequence 21 times (apply/patch/upload × 7).
_Avoid_: re-suggesting that `RemotePantryRepository`'s per-entity load/upsert/watch be
collapsed too — its wire mapping is **parity-critical, byte-for-byte** with the Flutter
client and its wrappers are already thin over shared cores; the `EntityPlan` references
them via closures rather than touching them. The repo `save` names
(`saveItems`/`saveRecipes`/`saveEntries`) are likewise left as-is and bound by closure,
not renamed.

## Flagged ambiguities

- "ingredient" — both inventory rows AND recipe-required food. Resolved: **Ingredient** = inventory row only; recipes use "recipe ingredient" / "required food".
- "draft" — used loosely. Resolved: code-level data type (`IngredientDraft`, `RecipeDraft`) vs **Proposal** as the conceptual unit being reviewed.
- "粘性 / stickiness" — used at project start to mean "feature richness". Resolved: this is a **self-use** app (A-mode); the real goal is "low-friction utility for the maintainer", not user retention. Avoid "粘性" in design discussions.
