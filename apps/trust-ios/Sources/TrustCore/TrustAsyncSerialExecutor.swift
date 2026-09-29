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
}
