import Foundation
import StepMossaicDomain

extension FrozenMarimoRecord {
  /// Builds a record from a frozen marimo, storing its month as a sortable key.
  convenience init(_ marimo: FrozenMarimo) {
    self.init(
      yearMonth: marimo.yearMonth.storageKey,
      sizeUnit: marimo.sizeUnit,
      colorLevel: marimo.colorLevel,
      bumpiness: marimo.bumpiness,
      seed: marimo.seed,
      totalSteps: marimo.totalSteps,
      frozenAt: marimo.frozenAt,
      isLocked: marimo.isLocked
    )
  }

  /// Overwrites an existing record's parameters from a regenerated marimo.
  ///
  /// `yearMonth` is the identity key and never changes here; only the snapshot
  /// parameters are refreshed (e.g. during the grace period before locking).
  func apply(_ marimo: FrozenMarimo) {
    sizeUnit = marimo.sizeUnit
    colorLevel = marimo.colorLevel
    bumpiness = marimo.bumpiness
    seed = marimo.seed
    totalSteps = max(0, marimo.totalSteps)
    frozenAt = marimo.frozenAt
    isLocked = marimo.isLocked
  }

  func toDomain() throws -> FrozenMarimo {
    guard let month = YearMonth(storageKey: yearMonth) else {
      throw PersistenceMappingError.malformedYearMonth(yearMonth)
    }
    return FrozenMarimo(
      yearMonth: month,
      sizeUnit: sizeUnit,
      colorLevel: colorLevel,
      bumpiness: bumpiness,
      seed: seed,
      totalSteps: totalSteps,
      frozenAt: frozenAt,
      isLocked: isLocked
    )
  }
}
