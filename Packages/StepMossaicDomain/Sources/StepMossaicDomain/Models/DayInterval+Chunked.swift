import Foundation

extension DayInterval {
  /// Splits the interval into contiguous sub-intervals of at most `maxDays` days.
  ///
  /// - Chunks are returned in chronological order, cover the whole interval with
  ///   no gaps or overlaps, and only the last one may be shorter than `maxDays`.
  /// - An interval that already fits within `maxDays` yields a single chunk equal
  ///   to itself.
  ///
  /// Used to drive the initial backfill progressively: a long history is fetched
  /// from HealthKit one bounded window at a time so progress can be reported and
  /// memory stays flat, rather than requesting a decade in one call.
  public func chunked(maxDays: Int, calendar: Calendar) -> [DayInterval] {
    precondition(maxDays >= 1, "DayInterval.chunked maxDays must be >= 1")

    var chunks: [DayInterval] = []
    var chunkStart = start
    while chunkStart <= end {
      // Inclusive bounds: a `maxDays`-long chunk ends `maxDays - 1` days later.
      let candidateEnd = chunkStart.adding(days: maxDays - 1, calendar: calendar)
      let chunkEnd = min(candidateEnd, end)
      chunks.append(DayInterval(start: chunkStart, end: chunkEnd))
      chunkStart = chunkEnd.adding(days: 1, calendar: calendar)
    }
    return chunks
  }
}
