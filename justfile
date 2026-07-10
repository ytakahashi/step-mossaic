# Set the default recipe to list all available recipes
default:
    @just --list

# Format all Swift files in-place
format:
    xcrun swift-format format --in-place --recursive --parallel \
      StepMossaic/StepMossaic \
      StepMossaic/StepMossaicTests \
      StepMossaic/StepMossaicUITests \
      Packages/StepMossaicDomain

# Lint all Swift files to check formatting rules
lint:
    xcrun swift-format lint --recursive --parallel --strict \
      StepMossaic/StepMossaic \
      StepMossaic/StepMossaicTests \
      StepMossaic/StepMossaicUITests \
      Packages/StepMossaicDomain

# Run the pure domain package tests
test-domain:
    swift test --package-path Packages/StepMossaicDomain

# Run app unit tests on a simulator (defaults to iPhone 17)
# Usage:
#   just test-app
#   just test-app "platform=iOS Simulator,name=iPhone 17"
test-app destination="platform=iOS Simulator,name=iPhone 17":
    xcodebuild test \
      -project StepMossaic/StepMossaic.xcodeproj \
      -scheme StepMossaicUnitTests \
      -destination "{{destination}}" | xcbeautify

# Run app UI tests on a simulator (defaults to iPhone 17)
# Usage:
#   just test-ui
#   just test-ui "platform=iOS Simulator,name=iPhone 17"
#   just test-ui "id=292EE662-6262-4FA4-B2CB-E3DAC5CBC9BC"
test-ui destination="platform=iOS Simulator,name=iPhone 17":
    xcodebuild test \
      -project StepMossaic/StepMossaic.xcodeproj \
      -scheme StepMossaicUITests \
      -destination "{{destination}}" | xcbeautify

# Build unit tests for testing (smoke check) without running tests on a booted simulator
build-test:
    xcodebuild build-for-testing \
      -project StepMossaic/StepMossaic.xcodeproj \
      -scheme StepMossaicUnitTests \
      -destination "generic/platform=iOS Simulator" | xcbeautify

# List available simulators and their IDs
list-simulators:
    xcrun simctl list devices available
