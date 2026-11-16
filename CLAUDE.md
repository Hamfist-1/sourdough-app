# Sourdough bake tracker

An iOS/iPadOS app (SwiftUI + SwiftData) for baking your own sourdough recipes: versioned recipes,
the bake in progress first, starter hydration driving the scaling.

## Read first

- `docs/DECISIONS.md` — what was decided and why. **The baking decisions come from the owner, an
  experienced baker; treat them as authoritative** (folds belong to bulk, mix method is by hand or
  machine, percentages are of total flour including starter flour, scaling is never a new version, …).
  Don't change them without asking.
- `docs/SPEC.md` — data model, the Build scaling math (§3), bake flow (§4), rules (§5), screens (§6).
- Visual flow: the whiteboard linked at the top of DECISIONS.md.

## Layout

- `SourdoughKit/` — Swift package with the logic, tested:
  - `BakeMath` — scaling engine (`BuildSolver`, `Formula`).
  - `BakeCore` — plans, step logs, choices, rules, display models (`FormulaSheet`, `ProcessSummary`),
    `RecipeWeights` (weights entry mode), formatting, units.
  - `BakeStore` — SwiftData models (`Recipe`, `RecipeVersion`, `Bake`), `BakeService`, container,
    sample data. Wrapped in `#if canImport(SwiftData)`.
- `App/` — the SwiftUI app (`App/Sources`, `App/Resources`).
- `project.yml` — XcodeGen definition. `Sourdough.xcodeproj` is generated and not committed.

## Commands (run from the repo root unless noted)

```bash
# Package tests (all three modules on macOS)
cd SourdoughKit && swift test

# Regenerate the Xcode project — required after adding, removing or renaming app files
xcodegen

# Build the app without opening Xcode
xcodebuild -project Sourdough.xcodeproj -scheme Sourdough -destination 'generic/platform=iOS Simulator' build -quiet
```

Before handing a change to the owner: run `swift test` and the `xcodebuild` build, and fix any errors.
The owner then runs it in the simulator from Xcode (⌘R) and gives feedback.

## Conventions

- Put logic in `SourdoughKit` with tests; keep views thin. Display text and rules (e.g. which rows
  are bold, rounding) live in `BakeCore` so they can be tested.
- Models stay CloudKit-ready: defaults or optionals everywhere, optional relationships with inverses,
  no unique constraints. Plans and logs are Codable structs stored as JSON `Data`.
- Choice fields in plans/logs use `@Lenient` so removing or renaming a choice never breaks stored data.
- Every percentage is a fraction of total flour (starter flour included). The flour blend is shares of
  the flour you add.
- Temperatures are stored in °C and shown in the user's unit (°F default). Weights are grams.
- When an `enum` gains a case, check `App/Sources/AppNavigation.swift` (`describe(_:)`) and other
  switches in the app.
- Keep `docs/SPEC.md` and `docs/DECISIONS.md` up to date when behavior changes; record the owner's
  feedback in DECISIONS.md with the reason.
- During development, a model change can crash the app on launch; delete the app from the simulator.

## Status

- Done: spec, scaling engine, models, Xcode project, chunk 1 (recipe page with the formula sheet,
  version editor with percentages/weights entry, Build). Chunk 1 is in the owner's review.
- Next: chunk 2 — step screens (Mix, Bulk, Shape, Proof, Cold, Bake) and timers with notifications;
  then chunk 3 — Evaluate, Summary, Compare.
