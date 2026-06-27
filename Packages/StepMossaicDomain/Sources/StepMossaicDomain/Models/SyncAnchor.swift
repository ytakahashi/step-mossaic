import Foundation

/// Marks how far the daily-step cache has been synced from HealthKit.
///
/// Only the last synced date is tracked: aggregation uses
/// `HKStatisticsCollectionQuery` over daily buckets, so differential sync re-reads
/// from `lastSyncedDate` rather than resuming an `HKQueryAnchor`. There is no
/// opaque anchor payload to persist.
public struct SyncAnchor: Equatable, Sendable {
  public var lastSyncedDate: Date

  public init(lastSyncedDate: Date) {
    self.lastSyncedDate = lastSyncedDate
  }
}
