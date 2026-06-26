import Foundation
import StepMossaicDomain
import SwiftData

@testable import StepMossaic

/// Fixed UTC calendar so day normalization is deterministic in store tests.
let testCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

/// Builds an in-memory SwiftData context for store tests.
///
/// Each call gets its own store so tests stay isolated, and nothing touches the
/// on-disk container the app uses.
@MainActor
enum InMemoryStore {
  static func makeContext() throws -> ModelContext {
    let schema = Schema([
      DailyStepLogRecord.self,
      FrozenMarimoRecord.self,
      SyncAnchorRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
  }
}

/// A fixed UTC date at midnight, so day-keyed records compare cleanly in tests.
func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
  testCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

/// The `Day` for a calendar date under the fixed UTC calendar.
func makeDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
  Day(containing: makeDate(year, month, day), calendar: testCalendar)
}
