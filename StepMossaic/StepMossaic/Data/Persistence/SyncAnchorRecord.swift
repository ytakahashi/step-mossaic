import Foundation
import SwiftData

@Model
final class SyncAnchorRecord {
  @Attribute(.unique) var id: String
  var lastSyncedDate: Date

  init(id: String = "healthkit.steps", lastSyncedDate: Date) {
    self.id = id
    self.lastSyncedDate = lastSyncedDate
  }
}
