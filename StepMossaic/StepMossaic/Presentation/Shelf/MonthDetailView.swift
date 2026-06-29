import SwiftUI

struct MonthDetailView: View {
  var monthLabel: String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        // Placeholder until the month's frozen marimo is wired up.
        Circle()
          .fill(Color.green.opacity(0.5))
          .frame(width: 150, height: 150)
          .frame(maxWidth: .infinity)
        HeatmapPlaceholder(title: monthLabel)
      }
      .padding()
    }
    .navigationTitle(monthLabel)
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    MonthDetailView(monthLabel: "2026.06")
  }
}
