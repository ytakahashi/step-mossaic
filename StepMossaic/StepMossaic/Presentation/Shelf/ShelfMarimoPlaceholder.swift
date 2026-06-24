import SwiftUI

struct ShelfMarimoPlaceholder: View {
  var index: Int

  var body: some View {
    VStack(spacing: 10) {
      Circle()
        .fill(Color.green.opacity(0.45 + Double(index % 3) * 0.12))
        .frame(width: 72, height: 72)

      Text("2026.\(index + 1)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(width: 88, height: 110)
  }
}

#Preview {
  ShelfMarimoPlaceholder(index: 2)
    .padding()
}
