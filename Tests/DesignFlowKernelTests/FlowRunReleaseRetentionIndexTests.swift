import DesignFlowKernel
import Foundation
import Testing
import DesignFlowKernel

@Suite("Release retention index")
struct FlowRunReleaseRetentionIndexTests {
    private static let evaluationDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("retention index builder validates a hash-chained append-only history")
    func builderProducesPassedIndex() async throws {
        let root = try makeTemporaryRoot("release-retention-index")
        defer { removeTemporaryRoot(root) }

        let index = try await makeIndex(root: root)

        #expect(index.status == .passed)
        #expect(index.appendOnly)
        #expect(index.appended)
        #expect(index.historyEntryCount == 1)
        #expect(index.diagnostics.isEmpty)
    }

    @Test("tampered history is blocked by digest and chain verification")
    func tamperedHistoryBlocks() async throws {
        let root = try makeTemporaryRoot("release-retention-tamper")
        defer { removeTemporaryRoot(root) }

        let index = try await makeIndex(root: root)
        let historyURL = root.appending(path: ".xcircuite/retention/history.jsonl")
        var tampered = try Data(contentsOf: historyURL)
        tampered.append(Data("\n".utf8))
        try tampered.write(to: historyURL, options: .atomic)

        let store = await TestFlowInfrastructure.bound(to: root)
        let result = try await DefaultFlowRunReleaseRetentionIndexValidator(
            persistence: store
        ).validate(
            index: index,
            runID: "run-1",
            projectRoot: root,
            currentDate: Self.evaluationDate,
            maximumAgeSeconds: nil
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "retention-index-history-digest-mismatch" })
        #expect(result.diagnostics.contains { $0.code == "retention-index-history-byte-count-mismatch" })
    }

    @Test("short retention window blocks release evidence")
    func shortRetentionWindowBlocks() async throws {
        let root = try makeTemporaryRoot("release-retention-short")
        defer { removeTemporaryRoot(root) }

        let index = try await makeIndex(root: root, retentionDays: 7, minimumRetentionDays: 30)

        #expect(index.status == .blocked)
        #expect(index.diagnostics.contains { $0.code == "retention-index-retention-window-too-short" })
    }

    @Test("history without a new appended entry blocks release evidence")
    func nonAppendingHistoryBlocks() async throws {
        let root = try makeTemporaryRoot("release-retention-no-append")
        defer { removeTemporaryRoot(root) }

        let index = try await makeIndex(root: root, previousEntryCount: 1)

        #expect(index.status == .blocked)
        #expect(index.diagnostics.contains { $0.code == "retention-index-not-append-only" })
        #expect(index.diagnostics.contains { $0.code == "retention-index-history-not-advanced" })
    }

    private func makeIndex(
        root: URL,
        previousEntryCount: Int = 0,
        retentionDays: Int = 30,
        minimumRetentionDays: Int = 30
    ) async throws -> FlowRunReleaseRetentionIndex {
        let store = await TestFlowInfrastructure.bound(to: root)
        let timestamp = timestamp(Self.evaluationDate)
        let dashboardData = Data(
            #"{"schemaVersion":1,"runID":"run-1","status":"passed","history":{"status":"passed"},"retainedSignoffSuite":{"status":"passed"}}"#.utf8
        )
        let dashboard = try await store.persistArtifact(
            content: dashboardData,
            id: ArtifactID(rawValue: "retention-dashboard"),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: "retention/dashboard.json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: "run-1",
            mode: .replaceable
        )
        var entry = FlowRunReleaseHistoryEntry(
            sequence: 1,
            entryID: "entry-1",
            runID: "run-1",
            recordedAt: timestamp,
            qualificationDigest: String(repeating: "c", count: 64),
            previousEntrySHA256: nil,
            entrySHA256: String(repeating: "0", count: 64)
        )
        entry.entrySHA256 = try entry.computedSHA256()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var historyData = try encoder.encode(entry)
        historyData.append(Data("\n".utf8))
        let history = try await store.persistArtifact(
            content: historyData,
            id: ArtifactID(rawValue: "retention-history"),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: "retention/history.jsonl"),
                role: .output,
                kind: .report,
                format: .text
            ),
            runID: "run-1",
            mode: .replaceable
        )

        let validator = DefaultFlowRunReleaseRetentionIndexValidator(persistence: store)
        return try await DefaultFlowRunReleaseRetentionIndexBuilder(
            persistence: store,
            validator: validator
        ).build(
            runID: "run-1",
            workflowRunID: "workflow-run-1",
            projectRoot: root,
            sourceDashboard: dashboard,
            history: history,
            previousEntryCount: previousEntryCount,
            retentionDays: retentionDays,
            minimumRetentionDays: minimumRetentionDays,
            recordedAt: Self.evaluationDate
        )
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "release-retention-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
