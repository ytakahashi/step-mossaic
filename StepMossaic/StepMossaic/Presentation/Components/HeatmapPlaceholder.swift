import SwiftUI

/// Static stand-in heatmap for screens not yet wired to live data (the Shelf
/// month detail). Home uses the live `StepHeatmapView`.
struct HeatmapPlaceholder: View {
  var title: String

  private let columns = Array(repeating: GridItem(.flexible(minimum: 8), spacing: 4), count: 14)

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.headline)

        Spacer()

        Text("0 avg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
        ForEach(0..<84, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2)
            .fill(color(for: index))
            .aspectRatio(1, contentMode: .fit)
        }
      }

      HStack {
        Text("0 total")
        Spacer()
        Text("Range")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func color(for index: Int) -> Color {
    switch index % 5 {
    case 0:
      Color.secondary.opacity(0.12)
    case 1:
      Color.green.opacity(0.25)
    case 2:
      Color.green.opacity(0.42)
    case 3:
      Color.green.opacity(0.62)
    default:
      Color.green.opacity(0.82)
    }
  }
}

#Preview {
  HeatmapPlaceholder(title: "Last 3 months")
    .padding()
}
