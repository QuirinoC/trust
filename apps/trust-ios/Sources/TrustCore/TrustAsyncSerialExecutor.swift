import Foundation

/// Runs asynchronous state mutations in submission order on the main actor.
@MainActor
public final class TrustAsyncSerialExecutor {
    private var tail: Task<Void, Never>?

    public init() {}

    public func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Serializes a mutation and lets callers wait until it has completed.
    public func enqueueAndWait(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        await task.value
    }
}
