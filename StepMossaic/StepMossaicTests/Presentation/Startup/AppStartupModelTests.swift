import Foundation
import Testing

@testable import StepMossaic

private struct TestError: Error {}

@MainActor
@Test("A container factory failure settles .persistenceFailure without crashing")
func startupFailureSettlesPersistenceFailure() async throws {
  // Arrange
  let model = AppStartupModel(makeContainer: { throw TestError() })

  // Act
  await model.start()

  // Assert
  guard case .persistenceFailure = model.state else {
    Issue.record("Expected .persistenceFailure, got \(model.state)")
    return
  }
}

@MainActor
@Test("A successful container factory settles .ready")
func startupSuccessSettlesReady() async throws {
  // Arrange
  let model = AppStartupModel(makeContainer: { try AppModelContainer.make(inMemory: true) })

  // Act
  await model.start()

  // Assert
  guard case .ready = model.state else {
    Issue.record("Expected .ready, got \(model.state)")
    return
  }
}

@MainActor
@Test("Retry re-invokes the container factory")
func retryReinvokesFactory() async throws {
  // Arrange: every attempt fails, so the model stays put between calls.
  var callCount = 0
  let model = AppStartupModel(makeContainer: {
    callCount += 1
    throw TestError()
  })
  await model.start()
  #expect(callCount == 1)

  // Act
  await model.retry()

  // Assert
  #expect(callCount == 2)
}

@MainActor
@Test("Retry succeeds after an initial failure, transitioning to .ready")
func retrySucceedsAfterInitialFailure() async throws {
  // Arrange: the first attempt fails; the underlying condition then clears.
  var shouldFail = true
  let model = AppStartupModel(makeContainer: {
    if shouldFail {
      shouldFail = false
      throw TestError()
    }
    return try AppModelContainer.make(inMemory: true)
  })
  await model.start()
  guard case .persistenceFailure = model.state else {
    Issue.record("Expected the first attempt to fail")
    return
  }

  // Act
  await model.retry()

  // Assert
  guard case .ready = model.state else {
    Issue.record("Expected .ready after retry, got \(model.state)")
    return
  }
}

@MainActor
@Test("Overlapping retry requests invoke the container factory only once")
func overlappingRetriesInvokeFactoryOnce() async throws {
  // Arrange: the initial attempt fails and puts the model in its recovery state.
  // The next factory call suspends until the test releases it, creating a
  // deterministic overlap window for the second retry.
  var callCount = 0
  var retryContinuation: CheckedContinuation<Void, Never>?
  let model = AppStartupModel(makeContainer: {
    callCount += 1
    if callCount == 1 { throw TestError() }
    await withCheckedContinuation { retryContinuation = $0 }
    return try AppModelContainer.make(inMemory: true)
  })
  await model.start()
  #expect(callCount == 1)

  // Act: hold the first retry inside the factory, then overlap a second request.
  let firstRetry = Task { await model.retry() }
  while retryContinuation == nil { await Task.yield() }
  let overlappingRetry = Task { await model.retry() }
  await overlappingRetry.value
  #expect(callCount == 2)
  retryContinuation?.resume()
  retryContinuation = nil
  await firstRetry.value

  // Assert: only one retry reached the store-opening factory.
  #expect(callCount == 2)
  guard case .ready = model.state else {
    Issue.record("Expected .ready after the successful retry")
    return
  }
}

@MainActor
@Test("Repeated failures stay on the recovery screen")
func repeatedFailuresStayOnRecoveryScreen() async throws {
  // Arrange
  let model = AppStartupModel(makeContainer: { throw TestError() })
  await model.start()

  // Act
  await model.retry()
  await model.retry()

  // Assert
  guard case .persistenceFailure = model.state else {
    Issue.record("Expected .persistenceFailure to persist, got \(model.state)")
    return
  }
}

@MainActor
@Test("Diagnostics reports only the startup operation and coarse failure kind, never the raw error")
func startupDiagnosticsReportsOperationAndKindOnly() async throws {
  // Arrange
  var reported: [(DiagnosticOperation, DiagnosticOutcome)] = []
  let model = AppStartupModel(
    makeContainer: { throw TestError() },
    reporter: { operation, outcome in reported.append((operation, outcome)) }
  )

  // Act
  await model.start()

  // Assert: exactly one event, naming `.startup` and its coarse
  // classification — the closure's signature makes a raw `Error` or its
  // description structurally unreachable here.
  #expect(reported.count == 1)
  #expect(reported.first?.0 == .startup)
  #expect(reported.first?.1 == .failure(.persistence))
}

@MainActor
@Test("A successful startup reports success diagnostics")
func startupDiagnosticsReportsSuccess() async throws {
  // Arrange
  var reported: [(DiagnosticOperation, DiagnosticOutcome)] = []
  let model = AppStartupModel(
    makeContainer: { try AppModelContainer.make(inMemory: true) },
    reporter: { operation, outcome in reported.append((operation, outcome)) }
  )

  // Act
  await model.start()

  // Assert
  #expect(reported.count == 1)
  #expect(reported.first?.0 == .startup)
  #expect(reported.first?.1 == .success)
}
