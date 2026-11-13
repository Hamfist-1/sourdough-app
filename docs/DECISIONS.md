# Sourdough Bake Tracker — Decisions

Product and technical decisions made during planning, before any code.
The visual flow of the app lives on the whiteboard:
https://claude.ai/artifact/61zJdqzBS9ijYNVLWx2RJt

_Last updated: 2026-11-13_

## Product

| Topic | Decision | Why |
|---|---|---|
| Who it's for | The owner first, built well enough to share later (TestFlight, possibly the App Store) | Keeps v1 focused, but the code and UX stay clean enough to share without a rewrite |
| Devices | iPhone and iPad | iPad is handy on a kitchen counter; SwiftUI layouts adapt to both |
| Core idea | A logbook for following your own recipe: recipes have versions, the bake in progress comes first, starter hydration drives the scaling | From the whiteboard |

## Scope

**v1 (first usable version)**
- Recipes, with versions
- Build: scale a recipe version to a target dough mass and loaf count (the solver from the whiteboard)
- Bake in progress through every step: Mix → Bulk ferment → Shape and final proof (optional cold ferment) → Bake → Evaluate
- Bake summary (printable)
- Compare recipe versions side by side, with their bakes
- Share a bake summary (PDF/image) and share a recipe file

**Later**
- Trends across bakes (scores over time)
- Photos on bakes
- Export all data (CSV/JSON backup)
- Live Activity / Dynamic Island countdown

## Behavior

| Topic | Decision |
|---|---|
| Active bakes | One active bake at a time. Home shows it; with none, go to Recipes. |
| Abandoned bakes | Kept and marked `abandoned`, with whatever was logged |
| Temperatures | °F by default, °C available in settings |
| Weights | Always grams |
| Timers | Local notifications for timed steps (autolyse, folds, proof, bake), even when the app is closed |
| Required vs. optional fields | Only required fields can block a build. Required: each flour weight, water, salt, starter weight and starter hydration %. Everything else is optional and left off the summary when empty. |
| Recipe pre-fill | Each step opens pre-filled from the recipe version. The bake always keeps its actuals. |
| Percentage basis | Every baker's percentage is measured against total flour, starter flour included. The build is calculated as a whole, then the starter's flour and water are backed out to get what goes on the scale. This matches the owner's manual method. |
| Starter hydration | Entered as a percentage (water ÷ flour), not a parts ratio, so stiff starters and bigas at odd hydrations (for example 55%) fit exactly |
| Versions are frozen once baked | A version with a completed bake can never be edited. Any planned change made to it, at Build or later, saves as a new version (or a new recipe) when the bake completes. The aim is to fix a recipe, change one variable at a time and track the effect. This may feel strict to other bakers later; revisit before a public release. |
| Planned change vs. actual | Only deliberate changes to planned values count as a variation. Actuals that differ from the plan (bulk running 30 minutes long) are logged, not treated as a new version. |
| Starter timing | Part of the recipe's process plan: "with the first mix (before autolyse)" or "after autolyse". Pre-filled, one tap to change, and it can be the single variable a new version tests. |
| Rise (bulk and proof) | Picked from 25% steps (25–150%) or "not measured", because it is judged by eye |

## Technical

| Topic | Decision | Notes |
|---|---|---|
| UI | SwiftUI | |
| Minimum iOS | iOS 17+ | Required for SwiftData |
| Persistence | SwiftData, designed to sync with iCloud (CloudKit) | Runs on the device alone until a paid Apple Developer account exists, then sync is switched on |
| CloudKit constraints | Every field optional or with a default; no unique constraints; relationships optional | Applies to the data model from day one, so sync can be enabled without a migration |
| Coding workflow | Claude writes the Swift; the owner reviews, runs it in Xcode and steers | |
| Repo | GitHub: `Hamfist-1/sourdough-app` | Off-machine backup and access from cloud sessions |

## Open items

- **Apple Developer account ($99/yr):** not yet decided. Needed for iCloud sync, TestFlight, and keeping the app installed on a device longer than 7 days.

## Next steps

1. ~~Write `docs/SPEC.md`~~ — done; see [SPEC.md](SPEC.md) (open questions resolved).
2. ~~Implement and test the scaling engine~~ — done; see [SourdoughKit](../SourdoughKit/README.md) (`BakeMath`).
3. ~~Write the SwiftData models~~ — done; see [SourdoughKit](../SourdoughKit/README.md) (`BakeCore`, `BakeStore`). `BakeStore` still needs its first compile on a Mac.
4. ~~Set up the Xcode project~~ — done (XcodeGen, `project.yml`; app shell in `App/`).
5. Build the screens in the order a bake happens.
