import Foundation
import OSLog

/// Default `DiagnosticsReporter`: writes to the on-device unified log only,
/// for diagnosing startup/sync failures after the fact (e.g. Console.app or a
/// sysdiagnose). Never sent off-device — Step Mossaic has no analytics or
/// crash-reporting SDK.
///
/// Only the operation name and the coarse `DiagnosticFailureKind` are logged,
/// both `.public`: the caller has already discarded the underlying `Error`
/// before calling this, so there is nothing here that could carry step
/// counts, dates, or other HealthKit/SwiftData detail.
enum DiagnosticsLogger {
  /// `.startup` gets its own category (container creation/retry); every other
  /// operation is a `StepSyncCoordinator` turn and logs under `Sync`, matching
  /// the category split in `M6_S2_ERROR.md` §7.
  private static let startupLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "StepMossaic", category: "Startup")
  private static let syncLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "StepMossaic", category: "Sync")

  @MainActor
  static func report(_ operation: DiagnosticOperation, _ outcome: DiagnosticOutcome) {
    let logger = operation == .startup ? startupLogger : syncLogger
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
