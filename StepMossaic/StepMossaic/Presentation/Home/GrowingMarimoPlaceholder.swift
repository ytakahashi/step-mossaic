import SwiftUI

struct GrowingMarimoPlaceholder: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("This month")
        .font(.headline)

      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [
                Color.green.opacity(0.72),
                Color.teal.opacity(0.5),
              ],
              center: .topLeading,
              startRadius: 8,
              endRadius: 96
            )
          )
          .frame(width: 160, height: 160)

        Circle()
          .stroke(.white.opacity(0.35), lineWidth: 1)
          .frame(width: 160, height: 160)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 190)
    }
  }
}

#Preview {
  GrowingMarimoPlaceholder()
    .padding()
}
