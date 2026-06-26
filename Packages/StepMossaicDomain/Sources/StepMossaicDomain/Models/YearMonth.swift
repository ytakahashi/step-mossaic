import Foundation

public struct YearMonth: Hashable, Comparable, Sendable {
  public var year: Int
  public var month: Int

  public init(year: Int, month: Int) {
    precondition((1...12).contains(month), "Month must be in 1...12")
    self.year = year
    self.month = month
  }

  public init(date: Date, calendar: Calendar = .current) {
    let gregorianCalendar = calendar.stepMossaicGregorian
    let components = gregorianCalendar.dateComponents([.year, .month], from: date)
    self.init(year: components.year ?? 1970, month: components.month ?? 1)
  }

  public var storageKey: String {
    String(format: "%04d-%02d", year, month)
  }

  /// Reconstructs a `YearMonth` from a `storageKey` ("YYYY-MM").
  ///
  /// The exact inverse of `storageKey`: only the canonical, zero-padded form
  /// round-trips. Anything else returns `nil`, including a non-padded month
  /// ("2026-6") or year ("7-06"). The key is machine-written, so a non-canonical
  /// string signals corruption or format drift and is surfaced rather than
  /// silently coerced.
  public init?(storageKey: String) {
    let fields = storageKey.split(separator: "-", omittingEmptySubsequences: false)
    guard fields.count == 2,
      let year = Int(fields[0]),
      let month = Int(fields[1]),
      (1...12).contains(month)
    else {
      return nil
    }
    let candidate = YearMonth(year: year, month: month)
    // Accept only the canonical form: re-encoding must reproduce the input, which
    // rejects non-padded fields without hardcoding field widths (year is min-4).
    guard candidate.storageKey == storageKey else {
      return nil
    }
    self = candidate
  }

  public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
    if lhs.year == rhs.year {
      return lhs.month < rhs.month
    }
    return lhs.year < rhs.year
  }
}
