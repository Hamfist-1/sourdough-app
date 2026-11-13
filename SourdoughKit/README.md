# SourdoughKit

The app's logic, as a Swift package the iOS app will depend on. Three modules:

| Module | What it holds | Spec | Runs on |
|---|---|---|---|
| `BakeMath` | The Build scaling engine: solve weights from any sufficient inputs, rescale from one weight, conflicts, rounding | [§3](../docs/SPEC.md#3-build-the-scaling-engine) | Anywhere |
| `BakeCore` | Value types and rules: process plans, bake plans, step logs, choices (rise, vessel…), variation detection, change notes, timers, °F/°C | [§2](../docs/SPEC.md#2-data-model), [§4](../docs/SPEC.md#4-bake-flow-state-machine), [§5](../docs/SPEC.md#5-rules) | Anywhere |
| `BakeStore` | SwiftData models (`Recipe`, `RecipeVersion`, `Bake`), `BakeService` (start, advance, abandon, complete, versions), the container and preview data | [§2](../docs/SPEC.md#2-data-model), [§5](../docs/SPEC.md#5-rules) | Apple platforms only |

`BakeStore` is wrapped in `#if canImport(SwiftData)`, so on Linux it compiles to nothing. Its tests only run on a Mac.

## Run the tests

On a Mac (runs all three modules' tests):

```bash
cd SourdoughKit
swift test
```

## Storage notes

- The models follow CloudKit's rules (defaults everywhere, optional relationships with inverses, no unique constraints), so iCloud sync can be switched on later in `BakeStoreContainer.make(cloudKit:)`.
- Formulas, plans and step logs are `Codable` values stored as JSON `Data` on the models, so adding a field later doesn't need a migration. Every field in them is optional for the same reason.
- Status and current step are stored as raw strings so they can be used in `#Predicate` queries.
