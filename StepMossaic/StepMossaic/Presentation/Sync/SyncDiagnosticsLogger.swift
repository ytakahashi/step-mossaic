import Foundation
import OSLog

/// Default `StepSyncModel.DiagnosticsReporter`: writes to the on-device unified
/// log only, for diagnosing sync failures after the fact (e.g. Console.app or
/// a sysdiagnose). Never sent off-device — Step Mossaic has no analytics or
/// crash-reporting SDK.
///
/// Only the operation name and the coarse `StepSyncModel.FailureKind` are
/// logged, both `.public`: `StepSyncModel` has already discarded the
/// underlying `Error` before calling this, so there is nothing here that could
/// carry step counts, dates, or other HealthKit/SwiftData detail.
enum SyncDiagnosticsLogger {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "StepMossaic", category: "Sync")

  @MainActor
  static func report(_ operation: StepSyncModel.SyncOperation, _ outcome: StepSyncModel.SyncOutcome)
  {
    switch outcome {
    case .success:
      logger.info("\(operation.rawValue, privacy: .public) succeeded")
    case .failure(let kind):
      logger.error(
        "\(operation.rawValue, privacy: .public) failed: \(String(describing: kind), privacy: .public)"
      )
    }
  }
}
