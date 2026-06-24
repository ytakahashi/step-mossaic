import SwiftUI

struct TodayStepsCard: View {
  var steps: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Today")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Text(steps, format: .number)
        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        .monospacedDigit()

      Text("steps")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  TodayStepsCard(steps: 8_432)
    .padding()
}
