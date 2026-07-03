import Foundation
import Observation
import StepMossaicDomain
import UIKit

/// Drives the Settings screen: Health authorization display/connection, and
/// triggering a full cache rebuild.
///
/// Talks to `StepSource` directly for authorization (same pattern as
/// `HomeViewModel`), and holds the app's single shared `StepSyncModel` to
/// trigger a rebuild — Settings does not own its own sync lifecycle.
@MainActor
@Observable
final class SettingsViewModel {
  private(set) var authorizationStatus: HealthAuthorizationStatus = .notDetermined

  private let source: any StepSource
  private let syncModel: StepSyncModel
  /// Opens a URL, injected so `openHealthSettings()` is testable without
  /// actually launching Settings.app; defaults to the real `UIApplication` call.
  private let openURL: (URL) -> Void

  init(
    source: any StepSource,
    syncModel: StepSyncModel,
    openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
  ) {
    self.source = source
    self.syncModel = syncModel
    self.openURL = openURL
  }

  /// Resolves the authorization status from the current source state.
  func refreshStatus() {
    authorizationStatus = source.authorizationStatus()
  }

  /// Prompts for HealthKit access, then re-resolves the status.
  ///
  /// Mirrors `HomeViewModel.requestAccess()`: lets someone who skipped or backed
  /// out of the Home prompt connect from Settings instead.
  func requestAccess() async {
    try? await source.requestAuthorization()
    refreshStatus()
  }

  /// Opens this app's page in Settings.app, where iOS surfaces the Health access
  /// toggle for apps with HealthKit read access. The only way to check or change
  /// a `.requested` status, since granted and denied read the same from the API.
  func openHealthSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
  }

  /// Wipes the cached daily logs and frozen marimos, then redrives a full
  /// backfill, via the shared sync model.
  func rebuildCache() async {
    await syncModel.rebuild()
  }
}
