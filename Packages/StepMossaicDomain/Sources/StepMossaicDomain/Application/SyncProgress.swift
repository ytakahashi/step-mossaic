/// Coarse progress of a step-data sync, surfaced so the UI can show a backfill
/// indicator without knowing how the coordinator stages its work.
///
/// Days, not chunks, are the unit of `backfilling` progress so the fraction is
/// stable regardless of the chunk size chosen for fetching.
public enum SyncProgress: Equatable, Sendable {
  /// Initial backfill in flight. `completedDays` advances toward `totalDays`.
  case backfilling(completedDays: Int, totalDays: Int)
  /// Differential sync of the recent window (no whole-history scan).
  case syncing
  /// Sync finished; cached data is up to date.
  case finished
}
