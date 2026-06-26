import Foundation

/// A persisted record could not be mapped back to its domain value.
///
/// Surfaced rather than silently dropped: a record that fails to decode signals
/// store corruption, which the caller should be able to detect and recover from
/// (e.g. by triggering a cache rebuild) instead of seeing data vanish.
enum PersistenceMappingError: Error, Equatable {
  /// A `FrozenMarimoRecord.yearMonth` string was not a valid `YearMonth` key.
  case malformedYearMonth(String)
}
