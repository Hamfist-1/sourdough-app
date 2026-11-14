# Sourdough Bake Tracker — Spec (v1)

The data model, the Build scaling math, and the rules that tie recipes, versions and bakes together.
Decisions this spec relies on are in [DECISIONS.md](DECISIONS.md); the visual flow is on the
[whiteboard](https://claude.ai/artifact/61zJdqzBS9ijYNVLWx2RJt).

_Status: reviewed — open questions resolved (see [§7](#7-resolved-questions)). Ready to implement._

---

## 1. Core concepts

- **Recipe**: a named bread (for example "Country loaf"). Holds an ordered list of versions.
- **Recipe version**: one fixed formula (baker's percentages) plus a process plan (mix, bulk, proof, bake settings). Versions are numbered 1, 2, 3… within a recipe.
- **Bake**: one time you made bread from a version. It stores a snapshot of what was **planned** (the version, scaled, plus any changes for this bake) and what **actually** happened at each step.
- **Planned vs. actual**: every step screen opens with planned values pre-filled. Whatever the user saves is the actual. A field never touched is recorded as "as planned".

```
Recipe 1───* RecipeVersion 1───* Bake
                  │                 ├─ plan    (snapshot: formula + process, scaled)
                  │                 └─ actuals (Mix, Bulk, Shape, Proof, Cold, Bake, Evaluate)
                  └─ derivedFrom? ──> RecipeVersion  (for "vary", across recipes)
```

---

## 2. Data model

### 2.1 Persistence rules (CloudKit-ready SwiftData)

These apply to every `@Model` from day one, so iCloud sync can be switched on without a migration:

- Every stored property has a default value or is optional.
- No `@Attribute(.unique)`. Identity is a `UUID` field `id`, generated on creation.
- Every relationship is optional and has an explicit inverse.
- Deletes use `.cascade` from parent to children (Recipe → versions, version → bakes) only where stated; otherwise `.nullify`.
- Step logs and formula details are `Codable` structs stored as JSON `Data` on the model, not as separate models. This keeps the schema small and sync cheap, and adding a field later needs no migration (every field in them is optional). They are always read and written with their parent.
- Enums on models (status, current step) are stored as raw `String`s so they work in `#Predicate` queries.
- Choice fields inside plans and logs (mix method, folds, rise, shape, vessel…) load leniently: a stored choice that no longer exists reads as "not set" and the rest of the record is kept, so choice lists can change without migrations.

All internal units: **grams**, **°C**, **seconds** (durations) and **Date** (timestamps). Display converts temperatures to °F/°C per the setting.

### 2.2 Models

**`Recipe`** (`@Model`)

| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| name | String = "" | Required to save |
| notes | String = "" | |
| createdAt | Date | |
| isArchived | Bool = false | Hidden from the list, never deleted with its bakes |
| versions | [RecipeVersion]? | cascade |

**`RecipeVersion`** (`@Model`)

| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| number | Int = 1 | Next number within the recipe; never reused |
| isFrozen | Bool (computed) | True once any bake of this version is `completed`. Frozen versions are read-only (§5.3) |
| createdAt | Date | |
| changeNote | String = "" | "What changed from the previous version" |
| formula | Formula | Codable, §2.3 |
| process | ProcessPlan | Codable, §2.4 |
| recipe | Recipe? | inverse |
| derivedFrom | RecipeVersion? | Set when created by "vary" or "save as new version"; nullify |
| derivatives | [RecipeVersion]? | Inverse of `derivedFrom` (CloudKit needs every relationship to have one) |
| bakes | [Bake]? | nullify (deleting a version is blocked while it has bakes) |

**`Bake`** (`@Model`)

| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| status | BakeStatus = .active | `active`, `completed`, `abandoned` |
| startedAt | Date | |
| endedAt | Date? | Set on complete or abandon |
| currentStep | BakeStep = .mix | §4. A bake is created when Build is confirmed, so it starts at `mix` |
| version | RecipeVersion? | The version this bake started from |
| plan | BakePlan | Codable snapshot, §2.5 |
| mix | MixLog? | Codable, §2.6 |
| bulk | BulkLog? | |
| shape | ShapeLog? | Divide + final shape |
| proof | ProofLog? | Final proof |
| cold | ColdLog? | Only if cold fermented |
| oven | OvenLog? | The Bake step's log |
| evaluation | Evaluation? | |
| additions | [AdjunctAddition] = [] | Ad-hoc adjuncts logged during the bake |

Only one bake may have `status == .active` at a time (§5.1).

### 2.3 `Formula` (Codable)

All percentages are **decimal fractions of total flour** (0.72 = 72%), where total flour includes the flour inside the starter. See §3.1.

| Field | Type | Required | Notes |
|---|---|---|---|
| hydration | Double | yes | Total water ÷ total flour, starter water included |
| saltPct | Double | yes | |
| starterPct | Double | yes | Starter mass ÷ total flour |
| starterHydration | Double = 1.0 | yes | Starter water ÷ starter flour (1.0 = 100%, 0.55 = a 55% biga). Any value ≥ 0 |
| starterFlourType | String? | no | |
| flours | [FlourComponent] | yes (1 to 3) | Blend of the **added** flour; shares sum to 1.0 |
| adjuncts | [AdjunctComponent] = [] | no | |

`FlourComponent`: `type: String?` (white AP, whole wheat…), `share: Double` (fraction of added flour).
With one flour, its share is 1.0. With several, the app keeps shares summing to 1.0 (editing one rebalances the last-edited other; the UI shows an error if it can't).

`AdjunctComponent`: `name: String`, `pct: Double` (of total flour), `stage: AdjunctStage` (`build`, `bulk`, `finalProof`).

### 2.4 `ProcessPlan` (Codable)

Every field optional. These pre-fill the step screens.

| Group | Fields |
|---|---|
| Mix | `firstIn` (flourWater, flourWaterSalt, other + text), `starterTiming` (withFirstMix = default, afterAutolyse; only asked when there is an autolyse), `autolyse: Duration?` (nil = no autolyse), `mixMethod` (by hand, machine), `mixDuration` |
| Bulk | `strengthMethod` (slapAndFold, stretchAndFold, coilFold, none), `sets: Int?`, `setInterval: Duration?`, `targetRise: Rise?`, `expectedDuration: Duration?` |
| Shape | `finalShape` (boule, batard, banneton, loafPan, other + text) |
| Proof | `proofDuration: Duration?`, `proofTempC: Double?`, `coldFerment: Bool`, `coldDuration: Duration?`, `coldTempC: Double?` |
| Bake | `preheatTempC`, `vessel` (dutchOven, stone, steel, tray, other), `steam` (text), `coveredTempC`, `coveredDuration`, `uncoveredTempC`, `uncoveredDuration`, `scored: Bool?` |

### 2.5 `BakePlan` (Codable snapshot)

Written when the user finishes the Build step. Never changes after that (later edits go into actuals).

| Field | Notes |
|---|---|
| formula | Copy of the version's formula, with any changes made for this bake |
| process | Copy of the version's process plan, with any changes made for this bake |
| targetMass | Grams, required |
| loafCount | Int ≥ 1, required |
| weights | The solved gram weights (§3): each added flour, added water, salt, starter (and its flour/water split), each adjunct, total |
| solvedFrom | Which inputs the user gave (for display: "you set total + hydration") |
| variesFromVersion | Bool: true if formula or process differs from the version |

Snapshotting means a bake always shows exactly what it was baked from, even if the version is later edited (§5.3).

### 2.6 Step logs (Codable)

Each log holds **actuals**. A field left `nil` means "as planned"; the summary shows the planned value in that case.

| Log | Fields |
|---|---|
| `MixLog` | `firstIn`, `starterTiming`, `autolyseStart/End: Date?`, `autolyseContents`, `mixMethod`, `mixDuration`, `addedNow` (salt, starter, other), `doughTempC` |
| `BulkLog` | `start/end: Date`, `strengthMethod`, `sets`, `setInterval`, `roomTempC`, `doughTempStartC`, `doughTempReadings: [(Date, °C)]`, `targetRise: Rise?`, `actualRise: Rise?` |
| `ShapeLog` | `loaves: [LoafLog]` (weight g, finalShape, scored) — defaults to equal weights = bulk total ÷ loafCount |
| `ProofLog` | `start/end: Date`, `roomTempC`, `rise: Rise?` |
| `ColdLog` | `location` (fridge, other), `start/end: Date`, `tempC` |
| `OvenLog` | `preheatTempC`, `vessel`, `steam`, covered temp/duration, uncovered temp/duration, `tempChanges: [String]`, `start/end: Date` |
| `Evaluation` | Out of oven: `crustColour`, `ovenSpring` (1–10), `hasEar: Bool?`, `internalTempC`. Cooled: `crumb`, `crustTexture`, `flavour` (1–10), `coolingDuration`, `custom: [name: score]`. `overall` (1–10, required to finish), `worked`, `didnt`, `nextTime` (text) |

`AdjunctAddition`: `name`, `grams`, `stage` (bulk, finalProof), `at: Date`. Logged during a bake, not part of the scaling.

`Rise`: an enum of whole-step choices, `pct25, pct50, pct75, pct100, pct125, pct150`, plus `notMeasured`. Rise is judged by eye, so a picker beats a free number.

Durations are computed from start/end timestamps wherever both exist; they are never stored separately.

---

## 3. Build: the scaling engine

A pure Swift module (`BakeMath`) with no UI or SwiftData dependency, fully unit tested. It takes a formula plus the user's inputs and returns gram weights, or a conflict.

### 3.1 Definitions

| Symbol | Meaning |
|---|---|
| F | Total flour (added flour + flour in the starter) |
| h | Hydration (total water ÷ F) |
| s | Salt % |
| p | Starter % (starter mass ÷ F) |
| hₛ | Starter hydration (starter water ÷ starter flour) |
| φ | Starter flour fraction = 1 ÷ (1 + hₛ). 100% → 0.5; 55% → 0.645 |
| A | Sum of adjunct percentages |
| M | Total dough mass |

Derived weights:

```
starter        S  = p·F
starter flour  Sf = φ·S
starter water  Sw = (1−φ)·S
added flour    Fa = F − Sf          = F·(1 − pφ)
added water    Wa = h·F − Sw        = F·(h − p(1−φ))
salt              = s·F
adjunct i         = aᵢ·F
total mass     M  = F·(1 + h + s + A)
```

Each added flour type gets `share × Fa`.

Why total flour: it is how the owner does the math by hand (calculate the whole build including the starter, then back out the starter's flour and water). It also makes "overall hydration includes the starter's water" (whiteboard) exact, and `M = F(1 + h + s + A)` matches the whiteboard's solver formula.

### 3.2 Solving from what the user knows

The user's "flour" and "water" inputs mean **added** flour and **added** water, what they actually put on the scale. Salt %, starter % and starter hydration, and adjuncts always come from the formula.

| User gives | Solve |
|---|---|
| M + h | F = M ÷ (1 + h + s + A) |
| M + Fa | F = Fa ÷ (1 − pφ); h = M/F − 1 − s − A |
| M + Wa | F = (M − Wa) ÷ (1 + s + A + p(1−φ)); h = Wa/F + p(1−φ) |
| Fa + h | F = Fa ÷ (1 − pφ) |
| Wa + h | F = Wa ÷ (h − p(1−φ)) |
| Fa + Wa | F = Fa ÷ (1 − pφ); h = Wa/F + p(1−φ) |
| Version only | Use the stored h; ask for M (default) or Fa |
| Any single weight X with percentage x | F = X ÷ x, then everything rescales. For added flour x = 1 − pφ; for added water x = h − p(1−φ) |

When a solve produces a hydration different from the version's, the bake is marked `variesFromVersion` (§5.2).

### 3.3 Validation and conflicts

- **Required inputs** (block Build if missing or ≤ 0): M or another pair from the table, each flour share, s ≥ 0, p ≥ 0, starter hydration ≥ 0, loafCount ≥ 1.
- **Impossible results** (block with a message): Fa ≤ 0 (more starter flour than total flour); Wa < 0 ("the starter alone has more water than this hydration allows"); h outside 0.4–1.2 is a warning, not a block.
- **Over-determined input**: if the user fills three of {M, Fa, Wa, h}, solve from each pair. If the results disagree by more than 1 g in any weight or 0.5 percentage points in h, show the conflict and ask which value to drop.

### 3.4 Rounding

Calculate in `Double`; round only for display. Weights show as whole grams, except salt, adjuncts and anything under 20 g, which show to 0.1 g. The displayed total is the sum of the displayed parts, so it may differ from M by a gram or two; that's expected and not flagged.

### 3.5 Reference cases (become unit tests)

**A. Total + hydration.** M = 1000, h = 0.75, s = 0.02, p = 0.20, starter at 100%, no adjuncts.
F = 1000 ÷ 1.77 = 564.97 → S = 112.99 (Sf 56.50, Sw 56.50), Fa = 508.47, Wa = 367.23, salt = 11.30. Parts sum to 999.99 ✓

**B. Whiteboard example.** M = 1200, h = 0.63, s = 0.02, p = 0, A = 0 → F = 727.27, water = 458.18, salt = 14.55.

**C. Added flour + added water.** Fa = 500, Wa = 375, s = 0.02, p = 0.20, starter at 100%.
F = 500 ÷ 0.9 = 555.56; h = 375/555.56 + 0.1 = 0.775; S = 111.11; salt = 11.11; M = 997.22.

**D. Stiff biga at an odd hydration.** p = 0.20, hₛ = 0.55 (φ = 0.6452), h = 0.70, Fa = 500 → F = 500 ÷ 0.87097 = 574.07; S = 114.81 (Sf 74.07, Sw 40.74); Wa = 401.85 − 40.74 = 361.11. Check: F − Sf = 500 ✓

**E. Impossible.** p = 1.0, starter at 100%, h = 0.40 → Wa = F(0.40 − 0.50) < 0 → error.

**F. Single-weight rescale.** From case A, set salt to 12 g → F = 600, everything rescales by 600/564.97.

---

## 4. Bake flow (state machine)

```
build → mix → bulk → shape → proof → (cold)? → bake → evaluate → completed
                                        any step ──abandon──> abandoned
```

- `BakeStep`: `build, mix, bulk, shape, proof, cold, bake, evaluate`.
- **Autolyse** is part of `mix`, not its own step.
- **Moving on**: "Next step" saves the current log and advances. The user can go back and edit any earlier log while the bake is active, and the logs of completed or abandoned bakes stay editable.
- **Cold ferment**: at the end of `proof`, the user chooses "bake now" (skip `cold`) or "cold ferment". The plan's `coldFerment` sets the default.
- **Completing**: saving `evaluate` with an `overall` score marks the bake `completed`, sets `endedAt`, builds the summary, then asks the version question in §5.3.

### 4.1 Timers and notifications

- Timed items: autolyse, each fold interval, bulk (expected duration), final proof, cold ferment, covered bake, uncovered bake.
- Starting one stores its start `Date` in the step log and schedules a local notification. The countdown is always computed from the stored date, never a running counter, so it survives the app being closed or killed.
- Notification ids: `bake-<bakeID>-<timer>`. Advancing past a step, abandoning, or completing cancels that bake's pending notifications.
- Ask for notification permission the first time a timer starts, not at launch.

---

## 5. Rules

### 5.1 One active bake
Starting a bake while another is active asks to finish or abandon the active one first. Home shows the active bake; with none, it opens Recipes.

### 5.2 Variation vs. actuals
Two different things, handled differently:
- **A variation** is a deliberate change to a *planned* value: a different hydration at Build, a planned autolyse of 60 minutes instead of 30, starter after autolyse instead of with the first mix. The step screen marks it as a planned change (a "change plan" control, separate from logging). It updates the bake's plan and marks the bake `variesFromVersion`.
- **An actual** is what happened: bulk ran 30 minutes long, the dough was 2 °F cooler. Actuals are logged against the plan and never make a new version.

The "save as…" question waits until the bake is complete (§5.3), so baking isn't interrupted.

### 5.3 Frozen versions and new versions
The goal is to fix a recipe, change one variable at a time, and compare the results, so a baked version must never change underneath its bakes.

- **A version freezes** when its first bake is completed. From then on it is read-only. The version editor shows it locked, with "New version from this".
- **A version with no completed bakes** can still be edited freely (for example, while setting up a recipe before the first bake).
- **When a bake that varied completes**, the app asks:
  - **Save as a new version** (default): version n+1 of the same recipe, built from the bake's plan, with `derivedFrom` set. It asks for a change note and pre-fills one from the diff ("Hydration 72% → 75%").
  - **Save as a new recipe**: the same, but under a new recipe; `derivedFrom` links back for Compare.
- **Either way, the bake moves to the new version**, so it is compared under the formula it actually used. The original version keeps only the bakes that followed it, and only freezes if one of those completes.
- Abandoned bakes don't freeze a version and never prompt.

A bake always keeps its own plan and actuals, whatever is chosen. (This rule may feel strict to other bakers; revisit before a public release, perhaps as a setting.)

### 5.4 Deleting
- A version with bakes can't be deleted; archive the recipe instead.
- Deleting a bake asks for confirmation; deleting a recipe deletes its versions and requires that none has bakes (or archives instead).

---

## 6. Screens (v1)

| Screen | Purpose |
|---|---|
| Home | The active bake: current step, running timer, "next step". With no active bake, opens Recipes. |
| Recipes | List of recipes, newest version shown, search. |
| Recipe detail | Its versions, each with bake count and average overall score; new version; vary; compare. |
| Version editor | Formula (percentages, flour blend, starter, adjuncts) and process plan. |
| Build | The solver: enter any sufficient pair, see weights live, loaf count, conflicts. Starts the bake. |
| Step screens | Mix, Bulk, Shape, Proof, Cold, Bake, Evaluate: planned values pre-filled, actuals logged, timers. |
| Bake summary | One page: formula, timeline, conditions, bake, scores, notes. Empty optional fields hidden. Print and share as PDF. |
| Compare | Two versions side by side: changed fields highlighted, and their bakes with scores. |
| Settings | Temperature unit (°F default). Stored in `@AppStorage` (per device for now). |

**iPhone**: a tab bar (Bake, Recipes, Settings) with navigation stacks.
**iPad**: `NavigationSplitView` (recipes → versions → detail); the active bake stays reachable from the sidebar.

### 6.1 Sharing
- **Bake summary**: rendered with `ImageRenderer` into a PDF and shared through `ShareLink`.
- **Recipe file**: one recipe with all its versions (formula + process, no bakes), as JSON in a custom file type `.sourdough` (UTType `com.hamfist.sourdough.recipe`) with a `schemaVersion` field. Opening it in the app imports it as a new recipe; it never overwrites an existing one.

---

## 7. Resolved questions

1. **Percentage basis:** total flour, starter flour included. This matches the owner's manual method: calculate the whole build, then back out the starter's flour and water (§3.1).
2. **Starter input:** starter hydration as a percentage, not a parts ratio, so stiff starters and bigas at odd hydrations fit exactly (§2.3).
3. **Version changes:** a version freezes after its first completed bake; any planned change then becomes a new version or recipe. There is no "update this version" and no "this bake only" (§5.3).
4. **Starter timing:** stored in the version's process plan (default: with the first mix, before autolyse) and logged in Mix. Because it lives in the plan, it can be the single variable a new version tests (§2.4).
5. **Rise:** picked from 25% steps or "not measured" (§2.6).

---

## 8. Build order

1. `BakeMath` module + unit tests from §3.5 (no UI).
2. SwiftData models (§2) + a seed recipe for previews.
3. Recipes → Version editor → Build (end-to-end: create a recipe, scale it, start a bake).
4. Step screens + timers/notifications.
5. Evaluate → Summary → the §5.3 question.
6. Compare.
7. Sharing (summary PDF, recipe file).
8. iPad layout pass.
