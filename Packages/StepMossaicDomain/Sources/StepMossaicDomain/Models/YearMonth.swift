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
    let components = calendar.dateComponents([.year, .month], from: date)
    self.init(year: components.year ?? 1970, month: components.month ?? 1)
  }

  public var storageKey: String {
    String(format: "%04d-%02d", year, month)
  }

  public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
    if lhs.year == rhs.year {
      return lhs.month < rhs.month
    }
    return lhs.year < rhs.year
  }
}
