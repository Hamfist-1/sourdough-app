# BakeMath

The Build scaling engine for the sourdough bake tracker: pure Swift, no UI or SwiftData.
It implements [SPEC §3](../docs/SPEC.md#3-build-the-scaling-engine).

- `Formula`: a recipe version's baker's percentages (all against total flour, starter flour included).
- `BuildSolver.solve(_:_:)`: gram weights from any sufficient inputs (total, added flour, added water, hydration).
- `BuildSolver.rescale(_:hydration:setting:to:)`: rescales everything after one weight is edited.
- `WeightDisplay.rounded(_:precise:)`: display rounding.

## Run the tests

```bash
cd BakeMath
swift test
```

The tests include the six reference cases from SPEC §3.5.
