import SwiftData

enum AppModelContainer {
  static func make() throws -> ModelContainer {
    let schema = Schema([
      DailyStepLogRecord.self,
      FrozenMarimoRecord.self,
      SyncAnchorRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
