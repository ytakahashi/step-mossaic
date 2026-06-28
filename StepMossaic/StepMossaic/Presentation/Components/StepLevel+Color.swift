import StepMossaicDomain
import SwiftUI

extension StepHeatmapCellState {
  /// The fill for a heatmap cell.
  ///
  /// Three visually distinct families keep the domain's states readable at a
  /// glance: unavailable (no data) is the faintest, an available 0-step day is a
  /// neutral grey (deliberately not "no data"), and positive days ramp green by
  /// rank so relative activity reads as depth of color.
  func fill(positiveLevelCount: Int) -> Color {
    switch self {
    case .unavailable:
      return Color.secondary.opacity(0.06)
    case .available(_, let level):
      guard level.rawValue > 0 else { return Color.secondary.opacity(0.18) }
      // Ramp opacity across the rank so the darkest level reads as the busiest day.
      let fraction = Double(level.rawValue) / Double(max(positiveLevelCount, 1))
      return Color.green.opacity(0.25 + 0.6 * fraction)
    }
  }
}
