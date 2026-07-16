import Foundation

public struct DefaultFlowRunProgressSubscriber: FlowRunProgressSubscribing {
    private let progressStore: FlowRunProgressStore

    public init(progressStore: FlowRunProgressStore) {
        self.progressStore = progressStore
    }

    public func snapshot(
        request: FlowRunProgressSubscriptionRequest
    ) async throws -> FlowRunProgressSnapshot {
        try validate(request)
        return try await makeSnapshot(request: request)
    }

    public func waitForProgress(
        request: FlowRunProgressSubscriptionRequest
    ) async throws -> FlowRunProgressSnapshot {
        try validate(request)
        var current = try await makeSnapshot(request: request)
        guard request.waitForNewEvents, current.events.isEmpty, !current.isTerminal else {
            return current
        }
        guard request.timeoutMilliseconds > 0 else {
            return current
        }

        let deadline = Date().addingTimeInterval(Double(request.timeoutMilliseconds) / 1_000.0)
        while Date() < deadline {
            let remainingMilliseconds = max(0, Int(deadline.timeIntervalSinceNow * 1_000.0))
            let sleepMilliseconds = min(request.pollIntervalMilliseconds, remainingMilliseconds)
            guard sleepMilliseconds > 0 else {
                break
            }
            try await Task.sleep(nanoseconds: UInt64(sleepMilliseconds) * 1_000_000)
            current = try await makeSnapshot(request: request)
            if !current.events.isEmpty || current.isTerminal {
                return current
            }
        }

        return try await makeSnapshot(request: request)
    }

    public func followProgress(
        request: FlowRunProgressSubscriptionRequest,
        onEvent: @Sendable (FlowRunProgressEvent) async throws -> Void
    ) async throws -> FlowRunProgressSnapshot {
        try validate(request)
        let deadline = Date().addingTimeInterval(Double(request.timeoutMilliseconds) / 1_000.0)
        var cursor = request.afterSequence
        var latest = try await makeSnapshot(request: request)

        while true {
            let remainingMilliseconds = remainingMilliseconds(until: deadline, request: request)
            let shouldWait = remainingMilliseconds > 0
            let waitRequest = FlowRunProgressSubscriptionRequest(
                projectRoot: request.projectRoot,
                runID: request.runID,
                afterSequence: cursor,
                waitForNewEvents: shouldWait,
                timeoutMilliseconds: remainingMilliseconds,
                pollIntervalMilliseconds: request.pollIntervalMilliseconds,
                stopWhenRunFinished: request.stopWhenRunFinished
            )
            latest = try await waitForProgress(request: waitRequest)
            for event in latest.events {
                try await onEvent(event)
            }
            cursor = max(cursor, latest.latestSequence)

            if latest.isTerminal || remainingMilliseconds <= 0 {
                return latest
            }
            if latest.events.isEmpty {
                return latest
            }
        }
    }

    private func makeSnapshot(
        request: FlowRunProgressSubscriptionRequest
    ) async throws -> FlowRunProgressSnapshot {
        let allEvents = try await progressStore.loadProgressEvents(
            runID: request.runID
        )
        let filteredEvents = allEvents.filter { $0.sequence > request.afterSequence }
        let latestSequence = allEvents.last?.sequence ?? 0
        let terminalStatus = request.stopWhenRunFinished ? terminalStatus(from: allEvents) : nil
        return FlowRunProgressSnapshot(
            runID: request.runID,
            afterSequence: request.afterSequence,
            latestSequence: latestSequence,
            events: filteredEvents,
            terminalStatus: terminalStatus
        )
    }

    private func validate(_ request: FlowRunProgressSubscriptionRequest) throws {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.afterSequence >= 0 else {
            throw FlowRunProgressSubscriptionError.invalidSequence(request.afterSequence)
        }
        guard request.timeoutMilliseconds >= 0 else {
            throw FlowRunProgressSubscriptionError.invalidTimeoutMilliseconds(request.timeoutMilliseconds)
        }
        guard request.pollIntervalMilliseconds > 0 else {
            throw FlowRunProgressSubscriptionError.invalidPollIntervalMilliseconds(
                request.pollIntervalMilliseconds
            )
        }
    }

    private func terminalStatus(from events: [FlowRunProgressEvent]) -> FlowRunStatus? {
        events.reversed().first { event in
            event.kind == .runFinished && event.runStatus.map(isTerminalStatus) == true
        }?.runStatus
    }

    private func isTerminalStatus(_ status: FlowRunStatus) -> Bool {
        switch status {
        case .succeeded, .failed, .blocked, .cancelled, .partial:
            true
        case .created, .running:
            false
        }
    }

    private func remainingMilliseconds(
        until deadline: Date,
        request: FlowRunProgressSubscriptionRequest
    ) -> Int {
        guard request.timeoutMilliseconds > 0 else {
            return 0
        }
        return max(0, Int(deadline.timeIntervalSinceNow * 1_000.0))
    }
}
