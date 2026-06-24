import SwiftUI

struct MonthDetailView: View {
  var monthLabel: String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        GrowingMarimoPlaceholder()
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
