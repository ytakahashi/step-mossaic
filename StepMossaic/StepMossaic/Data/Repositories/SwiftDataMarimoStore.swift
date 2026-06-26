import Foundation
import StepMossaicDomain
import SwiftData

/// SwiftData-backed cache of frozen monthly marimo snapshots.
///
/// Main-actor isolated for the same reason as `SwiftDataStepLogStore`: a single
/// non-`Sendable` `ModelContext`, a tiny row count, and an isolated
/// `MarimoStore` conformance with all callers on the main actor.
@MainActor
final class SwiftDataMarimoStore {
  private let context: ModelContext

  init(context: ModelContext) {
    self.context = context
  }

  private func record(for yearMonth: YearMonth) throws -> FrozenMarimoRecord? {
    let key = yearMonth.storageKey
    let descriptor = FetchDescriptor<FrozenMarimoRecord>(
      predicate: #Predicate { $0.yearMonth == key }
    )
    return try context.fetch(descriptor).first
  }
}

extension SwiftDataMarimoStore: @MainActor MarimoStore {
  func frozenMarimo(for yearMonth: YearMonth) throws -> FrozenMarimo? {
    try record(for: yearMonth)?.toDomain()
  }

  /// Inserts a new month's snapshot or refreshes an existing one in place.
  ///
  /// Upsert keyed by month rather than insert-only: a month may be regenerated
  /// during its grace period before locking, and that must overwrite the same
  /// row instead of creating a duplicate.
  func save(_ marimo: FrozenMarimo) throws {
    if let existing = try record(for: marimo.yearMonth) {
      existing.apply(marimo)
    } else {
      context.insert(FrozenMarimoRecord(marimo))
    }
    try context.save()
  }

  /// Returns every frozen marimo, sorted ascending by month.
  ///
  /// `storageKey` is zero-padded ("YYYY-MM"), so lexical order matches
  /// chronological order and the shelf can render months in sequence.
  func allFrozen() throws -> [FrozenMarimo] {
    let descriptor = FetchDescriptor<FrozenMarimoRecord>(
      sortBy: [SortDescriptor(\.yearMonth, order: .forward)]
    )
    return try context.fetch(descriptor).map { try $0.toDomain() }
  }

  /// Deletes every frozen marimo, including locked months, for a cache rebuild.
  func reset() throws {
    try context.delete(model: FrozenMarimoRecord.self)
    try context.save()
  }
}
