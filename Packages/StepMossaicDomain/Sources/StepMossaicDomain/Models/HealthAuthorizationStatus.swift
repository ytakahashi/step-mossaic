/// What is knowable about read access to step data.
///
/// Deliberately coarse: for read-only HealthKit access the system reports the
/// same status whether the user granted or denied reading (a privacy measure),
/// so "denied" and "authorized" cannot be told apart from the status API. The
/// only reliable distinctions are whether access has been requested yet and
/// whether HealthKit exists on the device. Effective access is inferred
/// elsewhere from whether step data actually comes back (coverage).
public enum HealthAuthorizationStatus: Equatable, Sendable {
  /// HealthKit is not available on this device.
  case unavailable
  /// Access has not been requested yet; the app should prompt.
  case notDetermined
  /// Access has been requested. Whether reading is actually permitted is not
  /// knowable from the status API; confirm by whether data is returned.
  case requested
}
