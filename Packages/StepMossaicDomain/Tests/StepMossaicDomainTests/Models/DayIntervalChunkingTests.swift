import Foundation
import Testing

@testable import StepMossaicDomain

private let calendar = TestCalendar.utc

@Test("Splits a long interval into chunks no longer than maxDays")
func chunkedSplitsLongIntervalIntoBoundedChunks() {
  // Arrange: 25 days, chunked by 10.
  let interval = DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 1, 25))

  // Act
  let chunks = interval.chunked(maxDays: 10, calendar: calendar)

  // Assert: full days split as 10 + 10 + 5, only the last chunk shorter.
  #expect(chunks.count == 3)
  #expect(chunks[0] == DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 1, 10)))
  #expect(chunks[1] == DayInterval(start: makeDay(2026, 1, 11), end: makeDay(2026, 1, 20)))
  #expect(chunks[2] == DayInterval(start: makeDay(2026, 1, 21), end: makeDay(2026, 1, 25)))
}

@Test("Chunks cover the interval contiguously with no gaps or overlaps")
func chunkedCoversIntervalContiguously() {
  // Arrange
  let interval = DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 1, 25))

  // Act
  let chunks = interval.chunked(maxDays: 10, calendar: calendar)

  // Assert: endpoints match and each chunk starts the day after the previous ends.
  #expect(chunks.first?.start == interval.start)
  #expect(chunks.last?.end == interval.end)
  for (previous, next) in zip(chunks, chunks.dropFirst()) {
    #expect(next.start == previous.end.adding(days: 1, calendar: calendar))
  }
}

@Test("Returns a single chunk when the interval fits within maxDays")
func chunkedReturnsSingleChunkWhenItFits() {
  // Arrange: exactly maxDays long.
  let interval = DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 1, 10))

  // Act
  let chunks = interval.chunked(maxDays: 10, calendar: calendar)

  // Assert: a fitting interval is not split.
  #expect(chunks == [interval])
}

@Test("Splits an exact multiple into equal full chunks")
func chunkedSplitsExactMultipleIntoEqualChunks() {
  // Arrange: 20 days is exactly two 10-day chunks, leaving no remainder.
  let interval = DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 1, 20))

  // Act
  let chunks = interval.chunked(maxDays: 10, calendar: calendar)

  // Assert: no trailing short chunk when the length divides evenly.
  #expect(chunks.count == 2)
  #expect(chunks[1].end == makeDay(2026, 1, 20))
}

@Test("A single-day interval yields one single-day chunk")
func chunkedSingleDayInterval() {
  // Arrange
  let day = makeDay(2026, 1, 1)
  let interval = DayInterval(start: day, end: day)

  // Act & Assert
  #expect(interval.chunked(maxDays: 10, calendar: calendar) == [interval])
}
