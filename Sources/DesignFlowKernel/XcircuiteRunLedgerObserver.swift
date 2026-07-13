import Foundation

public actor XcircuiteRunLedgerObserver {
    private let store: any XcircuiteRunLedgerStoring
    private var observationTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<[XcircuiteRunSnapshot], any Error>.Continuation?

    public init(storage: any XcircuiteRunLedgerStoring) {
        self.store = storage
    }

    @available(*, deprecated, message: "Inject a ledger storage implementation with init(storage:).")
    public init(store: any XcircuiteRunLedgerStoring = XcircuitePackageStore()) {
        self.store = store
    }

    public func snapshots(
        projectRoot: URL,
        pollingInterval: Duration = .milliseconds(500)
    ) -> AsyncThrowingStream<[XcircuiteRunSnapshot], any Error> {
        shutdown()
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [XcircuiteRunSnapshot].self,
            throwing: (any Error).self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        let store = self.store
        observationTask = Task {
            var previous: [XcircuiteRunSnapshot]?
            while !Task.isCancelled {
                do {
                    let current = try store.listRunSnapshots(inProjectAt: projectRoot)
                    if current != previous {
                        continuation.yield(current)
                        previous = current
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                do {
                    try await Task.sleep(for: pollingInterval)
                } catch {
                    break
                }
            }
            continuation.finish()
        }
        return stream
    }

    public func shutdown() {
        observationTask?.cancel()
        observationTask = nil
        continuation?.finish()
        continuation = nil
    }

    deinit {
        observationTask?.cancel()
        continuation?.finish()
    }
}
