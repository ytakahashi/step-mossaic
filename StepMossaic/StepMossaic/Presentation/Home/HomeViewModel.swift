import Foundation
import Observation
import StepMossaicDomain

/// Drives the Home screen's today-steps section.
///
/// Talks to `StepSource` directly (no persistence yet): it resolves the HealthKit
/// authorization phase, reads today's total, and re-reads it on each live tick.
/// The observation loop is owned by `activate()`, which the view runs via
/// `.task(id:)` so SwiftUI cancels it on disappear or phase change.
@MainActor
@Observable
final class HomeViewModel {
  /// What the today section should present.
  enum Phase: Equatable {
    /// Authorization has not been resolved yet.
    case loading
    /// HealthKit exists but access has not been requested; prompt the user.
    case needsAuthorization
    /// HealthKit is not available on this device.
    case unavailable
    /// Access has been requested; today's total can be shown.
    case ready
  }

  private(set) var phase: Phase = .loading
  /// Today's total once read; `nil` until the first read completes.
  private(set) var todaySteps: Int?

  private let source: any StepSource
  private let calendar: Calendar

  init(source: any StepSource = HealthKitStepSource(), calendar: Calendar = .current) {
    self.source = source
    self.calendar = calendar
  }

  /// Resolves the authorization phase from the current status.
  func refreshPhase() {
    switch source.authorizationStatus() {
    case .unavailable: phase = .unavailable
    case .notDetermined: phase = .needsAuthorization
    case .requested: phase = .ready
    }
  }

  /// Prompts for HealthKit access, then re-resolves the phase.
  ///
  /// A failed request leaves the phase unchanged so the user can retry.
  func requestAccess() async {
    try? await source.requestAuthorization()
    refreshPhase()
  }

  /// When ready, reads today's total and then keeps it live until cancelled.
  ///
  /// Intended to be driven by `.task(id: phase)`: it returns immediately unless
  /// ready, and the trailing `for await` loop is torn down by task cancellation.
  func activate() async {
    guard phase == .ready else { return }
    await loadToday()
    for await _ in source.observeTodayUpdates() {
      await loadToday()
    }
  }

  /// Reads today's step total.
  ///
  /// Errors and "no data" both surface as 0: for read-only access HealthKit
  /// cannot confirm permission, so an empty result is shown as zero rather than
  /// an error state.
  func loadToday() async {
    let today = Day(containing: Date(), calendar: calendar)
    let interval = DayInterval(start: today, end: today)
    do {
      todaySteps = try await source.dailySteps(in: interval).first?.steps ?? 0
    } catch {
      todaySteps = 0
    }
  }
}
