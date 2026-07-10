# Step Mossaic

Step Mossaic is an iPhone app that visualizes daily walking rhythm with a heatmap and monthly marimo-like artifacts.

## Current Structure

```text
StepMossaic/
  StepMossaic.xcodeproj
  StepMossaic/
    App/                 App-level setup such as SwiftData container wiring
    Data/Persistence/    SwiftData cache models (@Model records)
    Data/Mapping/        Record <-> domain value conversions
    Data/Repositories/   SwiftData-backed StepLogStore / MarimoStore
    Presentation/        SwiftUI screens and shared UI components
  StepMossaicTests/
  StepMossaicUITests/

Packages/
  StepMossaicDomain/     Local Swift package for pure domain logic
```

## Architecture

The app is organized as MVVM with a layered dependency direction:

```text
Presentation -> Domain <- Data
```

- `StepMossaicDomain` is a local Swift package with no SwiftUI, SwiftData, UIKit, or HealthKit dependency.
- App-side `Data` implements the Domain store protocols against SwiftData
  (`SwiftDataStepLogStore`, `SwiftDataMarimoStore`); these are main-actor isolated
  because they wrap a single, non-`Sendable` `ModelContext`. The HealthKit
  `StepSource` implementation is not yet wired.
- App-side `Presentation` currently contains the initial `TabView` skeleton: Home, Shelf, and Settings.

## Verification

Following commands are also configured using [justfile](./justfile) (`just`) and [lefthook.yml](./lefthook.yml) (`lefthook`).

`xcbeautify` is optional but recommended for Xcode command output.

### Test Categories

- Domain package tests (`Packages/StepMossaicDomain/Tests`)
  - Pure domain logic.
  - Runs without an iOS simulator.
- App unit tests (`StepMossaic/StepMossaicTests`)
  - App-side unit tests, including SwiftData stores with in-memory persistence.
  - Run through the `StepMossaicUnitTests` scheme.
  - This scheme references only `StepMossaicTests.xctest`, so it does not build
    or sign the UI test bundle.
- UI tests (`StepMossaic/StepMossaicUITests`)
  - Launches the app in a simulator.
  - Run through the `StepMossaicUITests` scheme.
  - These are slower because Xcode must build, install, sign, and launch the app
    and UI test runner on a concrete simulator.

The app scheme (`StepMossaic`) remains available for normal app build/run
workflows. For command-line testing, prefer the dedicated unit/UI test schemes so
the intended test target is explicit.

### Run Tests

Run the pure domain package tests:

```sh
swift test --package-path Packages/StepMossaicDomain
```

Run app unit tests on a concrete simulator:

```sh
xcodebuild test \
  -project StepMossaic/StepMossaic.xcodeproj \
  -scheme StepMossaicUnitTests \
  -destination id=<SIMULATOR-UDID> | xcbeautify
```

Run UI tests only when needed:

```sh
xcodebuild test \
  -project StepMossaic/StepMossaic.xcodeproj \
  -scheme StepMossaicUITests \
  -destination id=<SIMULATOR-UDID> | xcbeautify
```

For a faster build-only smoke check, use a generic simulator destination. This
does not run tests on a booted simulator:

```sh
xcodebuild build-for-testing \
  -project StepMossaic/StepMossaic.xcodeproj \
  -scheme StepMossaicUnitTests \
  -destination 'generic/platform=iOS Simulator' | xcbeautify
```

List available simulator IDs:

```sh
xcrun simctl list devices available
```

## Format and Lint

Format Swift files:

```sh
xcrun swift-format format --in-place --recursive --parallel StepMossaic/StepMossaic StepMossaic/StepMossaicTests StepMossaic/StepMossaicUITests Packages/StepMossaicDomain
```

Lint Swift files:

```sh
xcrun swift-format lint --recursive --parallel --strict StepMossaic/StepMossaic StepMossaic/StepMossaicTests StepMossaic/StepMossaicUITests Packages/StepMossaicDomain
```
