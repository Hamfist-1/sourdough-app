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
| Required vs. optional fields | Only required fields can block a build. Required: each flour weight, water, salt, starter weight and starter flour:water ratio. Everything else is optional and left off the summary when empty. |
| Recipe pre-fill | Each step opens pre-filled from the recipe version. When the bake finishes, the app asks whether to update the version or save a new one; the bake always keeps its actuals. |

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

1. Write `docs/SPEC.md`: entities and fields, planned vs. actual values, the Build solver formulas, and the rules for versions.
2. Implement and test the scaling engine.
3. Write the SwiftData models.
4. Set up the Xcode project and build the screens in the order a bake happens.
