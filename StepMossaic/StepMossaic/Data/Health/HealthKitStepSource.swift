import Foundation
import HealthKit
import StepMossaicDomain

/// HealthKit-backed `StepSource`: the app's bridge to the system step data.
///
/// Aggregation is pushed into HealthKit (`HKStatisticsCollectionQuery` with a
/// cumulative sum over local-midnight-anchored daily buckets) so the app never
/// walks raw samples, however many there are. Marked `@unchecked Sendable`
/// because `HKHealthStore` is documented as thread-safe and `Calendar` is a value
/// type; there is no mutable shared state to protect.
final class HealthKitStepSource: StepSource, @unchecked Sendable {
  enum Failure: Error, Equatable {
    /// HealthKit is not available on this device (e.g. iPad without it).
    case healthDataUnavailable
  }

  private let healthStore: HKHealthStore
  /// Defines the local-day boundaries used to anchor and bucket totals.
  private let calendar: Calendar

  private var stepType: HKQuantityType { HKQuantityType(.stepCount) }

  init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
    self.healthStore = healthStore
    self.calendar = calendar
  }

  func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw Failure.healthDataUnavailable
    }
    // Read-only: the app never writes step data back to HealthKit.
    try await healthStore.requestAuthorization(toShare: [], read: [stepType])
  }

  /// Reports whether step read access has been requested yet.
  ///
  /// HealthKit reports the same status for granted and denied reads (a privacy
  /// measure), so this only distinguishes "not asked yet" from "asked"; the raw
  /// `.sharingDenied`/`.sharingAuthorized` split is collapsed into `.requested`.
  /// Whether reading actually works is determined by whether data comes back.
  func authorizationStatus() -> HealthAuthorizationStatus {
    guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
    switch healthStore.authorizationStatus(for: stepType) {
    case .notDetermined: return .notDetermined
    default: return .requested
    }
  }

  func earliestSampleDate() async throws -> Date? {
    // Ascending by start date, limit 1: the cheapest way to find the first day to
    // backfill from without scanning the whole history.
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: stepType)],
      sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
      limit: 1
    )
    let samples = try await descriptor.result(for: healthStore)
    return samples.first?.startDate
  }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] {
    // Bind locally so the enumeration closure captures a value, not `self`.
    let calendar = calendar
    let start = interval.start.start
    // `DayInterval` includes the final day, so query up to the start of the next
    // day: HealthKit's end bound and bucket enumeration are both exclusive of it.
    let endExclusive = interval.end.adding(days: 1, calendar: calendar).start
    let inRange = HKQuery.predicateForSamples(withStart: start, end: endExclusive)
    let descriptor = HKStatisticsCollectionQueryDescriptor(
      predicate: .quantitySample(type: stepType, predicate: inRange),
      options: .cumulativeSum,
      // `start` is already a local midnight (`Day.start`), so it is a valid anchor.
      anchorDate: start,
      intervalComponents: DateComponents(day: 1)
    )
    let collection = try await descriptor.result(for: healthStore)

    var result: [DailySteps] = []
    collection.enumerateStatistics(from: start, to: endExclusive) { statistics, _ in
      // No sum means no samples in the bucket; skip it so only measured days are
      // cached. A covered day without an entry is an available 0-step day.
      guard let sum = statistics.sumQuantity() else { return }
      let steps = Int(sum.doubleValue(for: .count()).rounded())
      let day = Day(containing: statistics.startDate, calendar: calendar)
      result.append(DailySteps(day: day, steps: steps))
    }
    return result
  }

  /// Emits a coarse "step data changed" signal for live foreground updates.
  ///
  /// The tick carries no value, so the consumer must re-read the *current* day's
  /// total itself on each tick. The observation window is pinned to the local day
  /// at stream creation: if the app stays foregrounded across midnight the stream
  /// keeps watching the previous day too, which only yields harmless extra ticks
  /// and never misses a change. Recreate the stream on foreground re-entry or a
  /// day rollover to re-pin it to the new day. Background delivery is not
  /// registered, so this matters only while foregrounded; the query stops when the
  /// stream is cancelled.
  func observeTodayUpdates() -> AsyncStream<Void> {
    let store = healthStore
    let type = stepType
    let todayStart = calendar.startOfDay(for: Date())
    let predicate = HKQuery.predicateForSamples(withStart: todayStart, end: nil)

    return AsyncStream { continuation in
      let query = HKObserverQuery(sampleType: type, predicate: predicate) {
        _, completionHandler, error in
        // Swallow transient observer errors: a single failure should not tear the
        // stream down. completionHandler must always be called.
        if error == nil {
          continuation.yield(())
        }
        completionHandler()
      }
      store.execute(query)
      continuation.onTermination = { _ in
        store.stop(query)
      }
    }
  }
}
