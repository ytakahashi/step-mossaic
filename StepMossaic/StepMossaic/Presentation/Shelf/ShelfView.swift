import SwiftUI

struct ShelfView: View {
  private let columns = [
    GridItem(.adaptive(minimum: 88), spacing: 16)
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(0..<6, id: \.self) { index in
            NavigationLink {
              MonthDetailView(monthLabel: "Month \(index + 1)")
            } label: {
              ShelfMarimoPlaceholder(index: index)
            }
            .buttonStyle(.plain)
          }
        }
        .padding()
      }
      .navigationTitle("Shelf")
    }
  }
}

#Preview {
  ShelfView()
}
