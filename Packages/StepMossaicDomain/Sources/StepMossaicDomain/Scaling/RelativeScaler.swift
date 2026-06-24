public enum RelativeScaler {
  public static func level(for steps: Int, in population: [Int]) -> Int {
    guard steps > 0 else {
      return 0
    }

    let positivePopulation = population.filter { $0 > 0 }.sorted()
    guard !positivePopulation.isEmpty else {
      return 0
    }

    let lowerCount =
      positivePopulation.firstIndex(where: { $0 >= steps }).map {
        positivePopulation.distance(from: positivePopulation.startIndex, to: $0)
      } ?? positivePopulation.count
    let percentile = Double(lowerCount) / Double(positivePopulation.count)

    switch percentile {
    case ..<0.25:
      return 1
    case ..<0.50:
      return 2
    case ..<0.75:
      return 3
    default:
      return 4
    }
  }
}
