import SwiftUI

struct HomeView: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          TodayStepsCard(steps: 0)
          GrowingMarimoPlaceholder()
          HeatmapPlaceholder(title: "Last 3 months")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
      .navigationTitle("Step Mossaic")
    }
  }
}

#Preview {
  HomeView()
}
