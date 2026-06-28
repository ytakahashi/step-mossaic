import SwiftData

enum AppModelContainer {
  /// Builds the app's SwiftData container.
  ///
  /// `inMemory` backs the store with volatile storage for previews and tests so
  /// they never touch the on-disk container the running app uses.
  static func make(inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema([
      DailyStepLogRecord.self,
      FrozenMarimoRecord.self,
      SyncAnchorRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
