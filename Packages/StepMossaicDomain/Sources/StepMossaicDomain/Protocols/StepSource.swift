import Foundation

/// The source of truth for step data (HealthKit), abstracted for the domain.
///
/// `Sendable` and async: unlike the persistence stores, this is the genuinely
/// concurrent boundary, safe to drive off the main actor.
public protocol StepSource: Sendable {
  /// The earliest instant any step sample exists, or `nil` if there is none.
  /// Used to bound the initial backfill.
  func earliestSampleDate() async throws -> Date?
  /// Daily step totals bucketed by local day over `interval`, both end days
  /// inclusive.
  ///
  /// Taking a `DayInterval` (not a raw start/end `Date`) makes the day-granular,
  /// inclusive bounds explicit and removes the off-by-one risk at the end of the
  /// range. Days with no samples are omitted; the domain treats a covered day
  /// without an entry as an available 0-step day, so empty buckets need not be
  /// materialized.
  func dailySteps(in interval: DayInterval) async throws -> [DailySteps]
  func observeTodayUpdates() -> AsyncStream<Void>
  func authorizationStatus() -> HealthAuthorizationStatus
  func requestAuthorization() async throws
}
