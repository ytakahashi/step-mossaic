import Foundation
import Testing

@testable import StepMossaicDomain

@Test("storageKey zero-pads year and month to a stable sortable key")
func yearMonthStorageKeyIsZeroPadded() {
  // Act & Assert
  #expect(YearMonth(year: 2026, month: 6).storageKey == "2026-06")
  #expect(YearMonth(year: 7, month: 12).storageKey == "0007-12")
}

@Test("Reconstructs from its own storageKey unchanged")
func yearMonthRoundTripsThroughStorageKey() {
  // Arrange
  let original = YearMonth(year: 2026, month: 6)

  // Act
  let restored = YearMonth(storageKey: original.storageKey)

  // Assert
  #expect(restored == original)
}

@Test("Rejects malformed storage keys")
func yearMonthRejectsMalformedStorageKeys() {
  // Act & Assert: wrong field count, non-integer fields, and out-of-range month
  // all yield nil rather than an invalid value.
  #expect(YearMonth(storageKey: "2026") == nil)
  #expect(YearMonth(storageKey: "2026-06-01") == nil)
  #expect(YearMonth(storageKey: "2026-XX") == nil)
  #expect(YearMonth(storageKey: "2026-13") == nil)
  #expect(YearMonth(storageKey: "2026-00") == nil)
}

@Test("Accepts only the canonical zero-padded form")
func yearMonthRejectsNonCanonicalStorageKeys() {
  // Act & Assert: a value that parses but is not how storageKey would encode it
  // is rejected, so init? stays the exact inverse of storageKey.
  #expect(YearMonth(storageKey: "2026-6") == nil)  // month not zero-padded
  #expect(YearMonth(storageKey: "7-06") == nil)  // year below the min 4 width
  #expect(YearMonth(storageKey: "2026-006") == nil)  // month over-padded
  #expect(YearMonth(storageKey: "+2026-06") == nil)  // signed field is non-canonical
}
