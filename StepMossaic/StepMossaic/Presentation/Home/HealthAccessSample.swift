import Foundation
import StepMossaicDomain

/// Deterministic stand-in step history, used only to illustrate what the app
/// builds while there is no real data to draw.
///
/// The sample is fed through the same `StepHeatmapGenerator` / `MarimoGenerator`
/// the live Home screen uses, so the illustration is the real pipeline with
/// stand-in input rather than a second set of hand-drawn visuals that would drift
/// away from the product. Nothing here is stored or mixed into the user's own
/// data; `HealthAccessRequestView` labels it as an example on screen.
enum HealthAccessSample {
  /// Days of stand-in history generated — long enough to fill the heatmap's
  /// default three-month range and to contain one complete calendar month for
  /// the marimo.
  private static let dayCount = 100

  /// The illustrative heatmap over the sample history ending at `today`.
  static func heatmap(
    endingAt today: Day,
    calendar: Calendar,
    levelScale: StepLevelScale = StepLevelScale()
  ) -> StepHeatmap {
    let interval = interval(endingAt: today, calendar: calendar)
    let daily = dailySteps(in: interval, calendar: calendar)
    return StepHeatmapGenerator.heatmap(
      for: interval,
      stepsByDay: Dictionary(uniqueKeysWithValues: daily.map { ($0.day, $0.steps) }),
      coverage: coverage(over: interval),
      calendar: calendar,
      levelScale: levelScale
    )
  }

  /// The illustrative marimo for the calendar month *before* `today`.
  ///
  /// Deliberately not the current month: the growing marimo is naturally tiny on
  /// the 2nd of a month, and an illustration that shrinks depending on when the
  /// app is opened shows the feature poorly. The previous month is always
  /// complete, so the sample always renders a fully grown marimo.
  static func marimo(
    endingAt today: Day,
    calendar: Calendar,
    config: MarimoGenerationConfig = MarimoGenerationConfig()
  ) -> MarimoParameters? {
    guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: today.start) else {
      return nil
    }
    let interval = interval(endingAt: today, calendar: calendar)
    return MarimoGenerator.parameters(
      for: YearMonth(date: previousMonth, calendar: calendar),
      daily: dailySteps(in: interval, calendar: calendar),
      coverage: coverage(over: interval),
      today: today,
      calendar: calendar,
      config: config
    )
  }

  private static func interval(endingAt today: Day, calendar: Calendar) -> DayInterval {
    DayInterval(start: today.adding(days: -(dayCount - 1), calendar: calendar), end: today)
  }

  private static func coverage(over interval: DayInterval) -> StepDataCoverage {
    StepDataCoverage(firstAvailableDay: interval.start, lastSyncedDay: interval.end)
  }

  private static func dailySteps(in interval: DayInterval, calendar: Calendar) -> [DailySteps] {
    interval.days(calendar: calendar).enumerated().map { index, day in
      DailySteps(day: day, steps: steps(dayIndex: index))
    }
  }

  /// A weekly rhythm plus a slower monthly drift and a seeded per-day jitter, with
  /// the occasional near-rest day.
  ///
  /// Keyed off the day index rather than a random generator so the illustration is
  /// byte-identical on every launch — a sample that reshuffles itself each time
  /// the screen appears reads as noise, not as an example of a walking pattern.
  private static func steps(dayIndex: Int) -> Int {
    let jitter = pseudoRandom(dayIndex)
    // A handful of quiet days, so the heatmap has pale cells and the marimo picks
    // up some edge texture instead of reading as one flat month.
    if jitter < 0.1 { return 600 + Int(jitter * 4_000) }

    let weekly = sin(Double(dayIndex) * 2 * .pi / 7)
    let monthly = sin(Double(dayIndex) * 2 * .pi / 31)
    let value = 7_200 + weekly * 2_400 + monthly * 1_800 + (jitter - 0.5) * 3_600
    return Int(max(0, value))
  }

  /// A stable `0..<1` value per day index, via the SplitMix64 finalizer.
  private static func pseudoRandom(_ index: Int) -> Double {
    var z = UInt64(bitPattern: Int64(index)) &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z % 10_000) / 10_000
  }
}
