import SwiftUI

/// A compact labelled step figure ("Today", "This month", …), so the Home header
/// can stack several stats tightly above the marimo.
struct StepStat: View {
  var title: String
  var steps: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(steps, format: .number)
          .font(.system(.title, design: .rounded, weight: .semibold))
          .monospacedDigit()
        Text("steps")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 12) {
    StepStat(title: "Today", steps: 8_807)
    StepStat(title: "This month", steps: 194_971)
  }
  .padding()
}
