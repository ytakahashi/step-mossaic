import Foundation
import SwiftData

@Model
final class SyncAnchorRecord {
  @Attribute(.unique) var id: String
  var anchorData: Data
  var lastSyncedDate: Date

  init(id: String = "healthkit.steps", anchorData: Data, lastSyncedDate: Date) {
    self.id = id
    self.anchorData = anchorData
    self.lastSyncedDate = lastSyncedDate
  }
}
