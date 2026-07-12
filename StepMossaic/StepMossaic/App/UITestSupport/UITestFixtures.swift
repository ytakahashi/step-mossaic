#if DEBUG
  import Foundation
  import StepMossaicDomain
  import SwiftData

  /// Seeds an in-memory `ModelContainer` with two full prior months plus the
  /// current month's step history, so the `withData` UI-test scenario renders
  /// real content (multiple frozen Shelf marimos, a growing Home marimo, a
  /// populated heatmap) without depending on HealthKit.
  ///
  /// Inserted directly through a `ModelContext` on the same container
  /// `AppEnvironment` will later open its own context on — SwiftData reads
  /// both contexts against the same underlying store, so no seeding hook is
  /// needed on `AppEnvironment` itself.
  enum UITestFixtures {
    static func seedSampleData(into container: ModelContainer) throws {
      let calendar = Calendar.current
      let context = ModelContext(container)
      let now = Date()
      let today = Day(containing: now, calendar: calendar)
      let thisMonth = YearMonth(date: now, calendar: calendar)
      let lastMonth = thisMonth.previous()
      let twoMonthsAgo = lastMonth.previous()

      // Two full prior months, so `refreshFrozenMarimos()` freezes more than one
      // month onto the Shelf — enough to test a multi-tile grid, not just that a
      // single tile exists.
      for month in [twoMonthsAgo, lastMonth] {
        for day in month.interval(calendar: calendar).days(calendar: calendar) {
          context.insert(record(for: day))
        }
      }

      // The current month through today, so the Home growing marimo and heatmap
      // have content instead of sitting on `.empty`.
      let thisMonthStart = thisMonth.interval(calendar: calendar).start
      for day in DayInterval(start: thisMonthStart, end: today).days(calendar: calendar) {
        context.insert(record(for: day))
      }

      // An anchor set to "now" so the app's own sync takes the cheap
      // differential path instead of re-backfilling (and possibly racing) over
      // this seeded data.
      context.insert(SyncAnchorRecord(lastSyncedDate: now))
      try context.save()
    }

    /// Varies steps deterministically by day so the heatmap and marimo show
    /// texture instead of a flat plateau.
    private static func record(for day: Day) -> DailyStepLogRecord {
      let dayOfMonth = Calendar.current.component(.day, from: day.start)
      let steps = 3000 + (dayOfMonth * 431) % 6000
      return DailyStepLogRecord(date: day.start, steps: steps, updatedAt: day.start)
    }
  }
#endif
