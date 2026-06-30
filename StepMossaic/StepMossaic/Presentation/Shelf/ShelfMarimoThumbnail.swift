import StepMossaicDomain
import SwiftUI

/// One frozen month on the shelf: its marimo drawn cheaply, with the month label.
///
/// Uses the lightweight `MarimoStyle.shelf` so a grid of these stays smooth while
/// scrolling — the same marimo (shape, colour, bumpiness) the month detail shows at
/// full fidelity, just with sparser texture that thumbnail size hides anyway.
struct ShelfMarimoThumbnail: View {
  let marimo: FrozenMarimo

  var body: some View {
    VStack(spacing: 8) {
      MarimoView(parameters: marimo.parameters, style: .shelf)
        // Square and filling the cell width, so the marimo is as large as the grid
        // column allows without distorting.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)

      Text(monthLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  /// `YYYY.MM`, zero-padded so widths stay even down the grid.
  private var monthLabel: String {
    String(format: "%04d.%02d", marimo.yearMonth.year, marimo.yearMonth.month)
  }
}

#Preview("Shelf thumbnails") {
  let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]
  let samples: [FrozenMarimo] = (0..<6).map { index in
    FrozenMarimo(
      yearMonth: YearMonth(year: 2026, month: 6 - index),
      sizeUnit: 0.3 + Double(index) * 0.12,
      colorLevel: 1 + Double(index % 4) * 0.7,
      bumpiness: 0.15 + Double(index % 3) * 0.2,
      seed: UInt64(202_600 + 6 - index),
      totalSteps: 120_000 + index * 30_000,
      frozenAt: .now,
      isLocked: true
    )
  }

  return ScrollView {
    LazyVGrid(columns: columns, spacing: 20) {
      ForEach(samples, id: \.yearMonth.storageKey) { marimo in
        ShelfMarimoThumbnail(marimo: marimo)
      }
    }
    .padding()
  }
}
