import Foundation
import StepMossaicDomain

extension SyncAnchorRecord {
  /// Copies the anchor payload onto an existing singleton record.
  ///
  /// The record `id` is a fixed singleton key, so saving an anchor updates the
  /// one row in place rather than accumulating history.
  func apply(_ anchor: SyncAnchor) {
    anchorData = anchor.anchorData
    lastSyncedDate = anchor.lastSyncedDate
  }

  func toDomain() -> SyncAnchor {
    SyncAnchor(anchorData: anchorData, lastSyncedDate: lastSyncedDate)
  }
}
