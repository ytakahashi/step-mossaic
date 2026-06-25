import Foundation
import Testing

@testable import StepMossaicDomain

@Test("Days within the synced range are available")
func coverageMarksDaysWithinRangeAvailable() {
  // Arrange
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act & Assert: both bounds are inclusive.
  #expect(coverage.isAvailable(makeDay(2026, 6, 1)))
  #expect(coverage.isAvailable(makeDay(2026, 6, 20)))
}

@Test("Days outside the synced range are unavailable, not zero steps")
func coverageMarksDaysOutsideRangeUnavailable() {
  // Arrange
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act & Assert: the days just outside each bound are unavailable.
  #expect(!coverage.isAvailable(makeDay(2026, 5, 31)))
  #expect(!coverage.isAvailable(makeDay(2026, 6, 21)))
}

@Test("Nil firstAvailableDay means no day is available")
func coverageWithoutFirstAvailableDayHasNoAvailability() {
  // Arrange: coverage with no available data at all.
  let coverage = StepDataCoverage(
    firstAvailableDay: nil,
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act & Assert: even a day before lastSyncedDay is unavailable.
  #expect(!coverage.isAvailable(makeDay(2026, 6, 10)))
}
