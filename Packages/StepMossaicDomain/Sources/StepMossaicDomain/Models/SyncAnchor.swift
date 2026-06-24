import Foundation

public struct SyncAnchor: Equatable, Sendable {
  public var anchorData: Data
  public var lastSyncedDate: Date

  public init(anchorData: Data, lastSyncedDate: Date) {
    self.anchorData = anchorData
    self.lastSyncedDate = lastSyncedDate
  }
}
