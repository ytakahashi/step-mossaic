import Foundation

@testable import StepMossaicDomain

/// Deterministic UTC Gregorian calendar shared by the date-foundation tests.
enum TestCalendar {
  static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  static let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()

  static let japaneseTokyo: Calendar = {
    var calendar = Calendar(identifier: .japanese)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()
}

/// Builds a `Day` from year/month/day components using a noon timestamp, so that
/// normalization to the start of the day is actually exercised.
func makeDay(
  _ year: Int,
  _ month: Int,
  _ day: Int,
  calendar: Calendar = TestCalendar.utc
) -> Day {
  var components = DateComponents()
  components.year = year
  components.month = month
  components.day = day
  components.hour = 12
  let date = calendar.date(from: components)!
  return Day(containing: date, calendar: calendar)
}
