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

- requires `xcbeautify`

```sh
swift test --package-path Packages/StepMossaicDomain
xcodebuild -project StepMossaic/StepMossaic.xcodeproj -scheme StepMossaic -destination 'generic/platform=iOS Simulator' | xcbeautify
```

## Format and Lint

Format Swift files:

```sh
xcrun swift-format format --in-place --recursive --parallel StepMossaic/StepMossaic StepMossaic/StepMossaicTests StepMossaic/StepMossaicUITests Packages/StepMossaicDomain/Sources Packages/StepMossaicDomain/Tests
```

Lint Swift files:

```sh
xcrun swift-format lint --recursive --parallel --strict StepMossaic/StepMossaic StepMossaic/StepMossaicTests StepMossaic/StepMossaicUITests Packages/StepMossaicDomain/Sources Packages/StepMossaicDomain/Tests
```
