# Sourdough

An iOS and iPadOS logbook for baking your own sourdough recipes: versioned recipes, the bake in progress first, and starter hydration driving the scaling.

- Plan: [docs/DECISIONS.md](docs/DECISIONS.md) and [docs/SPEC.md](docs/SPEC.md)
- Visual flow: [whiteboard](https://claude.ai/artifact/61zJdqzBS9ijYNVLWx2RJt)
- Logic and data: [SourdoughKit](SourdoughKit/README.md) (scaling engine, rules, SwiftData models)
- App: `App/` (SwiftUI)

## Setup (Mac)

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml`, so it isn't committed.

```bash
brew install xcodegen
```

```bash
xcodegen
```

```bash
open Sourdough.xcodeproj
```

Run `xcodegen` again after every `git pull`, so new files show up in Xcode.

Pick an iPhone or iPad simulator and press ⌘R. Running on a real device needs a signing team: set `DEVELOPMENT_TEAM` in `project.yml` (Xcode → Settings → Accounts shows your team ID).

## Tests

```bash
cd SourdoughKit
swift test
```
