import Foundation

/// One operation the app drives that is worth an on-device diagnostic event —
/// startup, or a turn of `StepSyncCoordinator` work — named for logging only.
///
/// Shared by `AppStartupModel` and `StepSyncModel` so both report through the
/// same `DiagnosticsReporter`/`DiagnosticsLogger` pair rather than each
/// maintaining its own near-identical operation/outcome vocabulary.
enum DiagnosticOperation: String {
  case startup
  case sync
  case refreshFrozenMarimos
  case coverage
  case rebuild
}

/// Coarse, privacy-safe classification of why an operation failed, kept
/// separate from any UI-facing state so no raw `Error` — which could carry
/// step counts, dates, or other HealthKit/SwiftData detail — ever reaches a
/// view or a log line.
enum DiagnosticFailureKind: Equatable {
  case source
  case persistence
  /// A failure that did not arrive as a recognized Domain failure type (not
  /// expected today; a defensive fallback for a future unclassified error).
  case unknown
}

/// The result of one `DiagnosticOperation`, reported without the underlying
/// `Error` so a diagnostics sink never sees HealthKit/SwiftData detail.
enum DiagnosticOutcome: Equatable {
  case success
  case failure(DiagnosticFailureKind)
}

/// Reports one operation's outcome for on-device diagnostics. Injected as a
/// closure rather than a concrete `Logger` so tests can assert what was
/// reported without touching OSLog; the composition root wires the real
/// implementation (`DiagnosticsLogger.report`).
typealias DiagnosticsReporter = @MainActor (DiagnosticOperation, DiagnosticOutcome) -> Void
