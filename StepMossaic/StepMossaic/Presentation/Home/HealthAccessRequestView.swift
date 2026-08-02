import StepMossaicDomain
import SwiftUI

/// The Home screen while Health access is still unresolved.
///
/// Two things have to hold here at once.
///
/// The screen has to show what the app *is*. The heatmap and the marimo are the
/// whole product, and gating them behind authorization left this screen as a
/// sentence and a button — nothing on it said the app turns step counts into
/// anything. So it renders a clearly labelled sample built by
/// `HealthAccessSample`, drawn with the same views the live screen uses.
///
/// And per App Store Review Guideline 5.1.1(iv) the pre-permission copy must not
/// push the user toward granting access: it may explain *what* is read and *why*,
/// but the button that raises the system prompt has to be neutral wording such as
/// "Continue" — never "Allow …".
struct HealthAccessRequestView: View {
  let onContinue: () async -> Void
  /// Injected so the sample's weekday alignment matches the live heatmap's.
  var calendar: Calendar = .current
  /// Injected for previews and tests; the sample is anchored to this day.
  var now: () -> Date = Date.init

  /// Rendered height of the sample marimo. Capped rather than left to fill the
  /// width, so the heatmap underneath stays on screen without scrolling.
  private let sampleMarimoHeight: CGFloat = 220

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      explanation
      Button("Continue") {
        Task { await onContinue() }
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("home.healthAccessContinueButton")
      sample
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Where the data comes from and where it stays — no encouragement to grant,
  /// which is what 5.1.1(iv) actually prohibits.
  ///
  /// Kept to two short lines: the sample below carries what the app makes, so
  /// spelling it out in prose would be the screen saying twice what it can show
  /// once (DESIGN §1, "UI コピー方針: 文章は最小限").
  private var explanation: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Made from your steps.")
        .font(.headline)
      Text("Read from Apple Health. Kept on this device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var sample: some View {
    let today = Day(containing: now(), calendar: calendar)
    let heatmap = HealthAccessSample.heatmap(endingAt: today, calendar: calendar)

    return VStack(alignment: .leading, spacing: 12) {
      // The one word that keeps the sample from reading as the user's own data.
      // It heads the whole group, so neither drawing needs its own disclaimer.
      Text("Example")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("home.healthAccessRequest.sampleLabel")

      if let parameters = HealthAccessSample.marimo(endingAt: today, calendar: calendar) {
        MarimoView(parameters: parameters)
          .frame(maxWidth: .infinity)
          .frame(height: sampleMarimoHeight)
          // Collapsed into one labelled element: the drawing is a Canvas with no
          // accessibility of its own, so without this the sample is an unlabelled
          // gap under VoiceOver — and nothing for a UI test to assert on either.
          .accessibilityElement()
          .accessibilityLabel("Example marimo")
          .accessibilityIdentifier("home.healthAccessRequest.sampleMarimo")
      }

      HeatmapGrid(
        weeks: HeatmapLayout.weeks(for: heatmap.cells, calendar: calendar),
        orderedWeekdaySymbols: calendar.orderedVeryShortWeekdaySymbols,
        positiveLevelCount: StepLevelScale().positiveLevelCount,
        referenceColumnCount: HeatmapLayout.weekCount(for: heatmap.interval, calendar: calendar)
      )
      // Inert: the grid's per-day popover would invite the user to inspect step
      // counts that aren't theirs. The cells are ignored for the same reason —
      // reading out 100 sample days is noise, so the sample speaks as one element.
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Example heatmap")
      .accessibilityIdentifier("home.healthAccessRequest.sampleHeatmap")
    }
  }
}

#Preview {
  HealthAccessRequestView(onContinue: {})
    .padding()
}
