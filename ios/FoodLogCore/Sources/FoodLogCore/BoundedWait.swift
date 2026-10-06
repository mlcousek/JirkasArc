// BoundedWait.swift
//
// "Wait for this, but not longer than N seconds" for an intent's inline
// delivery (add-garmin-auth-and-sync design D6: an intent may wait briefly
// for Garmin so it can say what happened, never long).
//
// The operation is NEVER cancelled when the wait runs out: a cancelled
// drain request would count as a failed attempt against the entry, so the
// drain simply finishes on its own and the caller gets `nil` ("not known
// yet"). `AppServices.briefDelivery` does exactly this for the food
// outbox; this is the same thing for any operation, written once and
// tested, for the weight and water intents (add-training-shortcuts-and-
// widgets design D5; Shared/QuickHealthLogIntents.swift).
//
// Tests: BoundedWaitTests.

import Foundation

public enum BoundedWait {
    /// The operation's value, or `nil` if it took longer than `seconds`.
    /// The operation keeps running either way.
    public static func value<Value: Sendable>(
        within seconds: Double,
        of operation: @escaping @Sendable () async -> Value
    ) async -> Value? {
        let work = Task { await operation() }
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let gate = ResumeGate(continuation)
            Task {
                let value = await work.value
                await gate.resume(value)
            }
            Task {
                try? await Task.sleep(nanoseconds: nanoseconds)
                await gate.resume(nil)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever side gets there first.
private actor ResumeGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
