import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import DesignFlowKernel

@Suite("Release retention index")
struct FlowRunReleaseRetentionIndexTests {
    private static let evaluationDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("retention index builder validates a hash-chained append-only history")
    func builderProducesPassedIndex() throws {
        let root = try makeTemporaryRoot("release-retention-index")
        defer { removeTemporaryRoot(root) }

        let index = try makeIndex(root: root)

        #expect(index.status == .passed)
        #expect(index.appendOnly)
        #expect(index.appended)
        #expect(index.historyEntryCount == 1)
        #expect(index.diagnostics.isEmpty)
    }

    @Test("tampered history is blocked by digest and chain verification")
    func tamperedHistoryBlocks() throws {
        let root = try makeTemporaryRoot("release-retention-tamper")
        defer { removeTemporaryRoot(root) }

        let index = try makeIndex(root: root)
        let historyURL = root.appending(path: "retention/history.jsonl")
        var tampered = try Data(contentsOf: historyURL)
        tampered.append(Data("\n".utf8))
        try tampered.write(to: historyURL, options: .atomic)

        let result = try DefaultFlowRunReleaseRetentionIndexValidator().validate(
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
    func shortRetentionWindowBlocks() throws {
        let root = try makeTemporaryRoot("release-retention-short")
        defer { removeTemporaryRoot(root) }

        let index = try makeIndex(root: root, retentionDays: 7, minimumRetentionDays: 30)

        #expect(index.status == .blocked)
        #expect(index.diagnostics.contains { $0.code == "retention-index-retention-window-too-short" })
    }

    @Test("history without a new appended entry blocks release evidence")
    func nonAppendingHistoryBlocks() throws {
        let root = try makeTemporaryRoot("release-retention-no-append")
        defer { removeTemporaryRoot(root) }

        let index = try makeIndex(root: root, previousEntryCount: 1)

        #expect(index.status == .blocked)
        #expect(index.diagnostics.contains { $0.code == "retention-index-not-append-only" })
        #expect(index.diagnostics.contains { $0.code == "retention-index-history-not-advanced" })
    }

    @Test("retention index CLI persists a release artifact and validates it")
    func cliBuildsAndValidatesRetentionIndex() async throws {
        let root = try makeTemporaryRoot("release-retention-cli")
        defer { removeTemporaryRoot(root) }

        _ = try makeIndex(root: root)
        let storage = XcircuiteWorkspaceStore()

        let build = try await DesignFlowCLICommand.runProcess(arguments: [
            "build-retention-index",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "run-1",
            "--workflow-run-id", "workflow-run-1",
            "--source-dashboard", "retention/dashboard.json",
            "--history", "retention/history.jsonl",
            "--previous-entry-count", "0",
            "--retention-days", "30",
            "--minimum-retention-days", "30",
        ])
        let buildData = try #require(build.output.data(using: .utf8))
        let buildResult = try JSONDecoder().decode(
            FlowRunReleaseRetentionIndexBuildResult.self,
            from: buildData
        )
        #expect(build.exitCode == 0)
        #expect(buildResult.index.status == .passed)
        #expect(buildResult.artifact.artifactID == "qualification-retention-index")

        let validation = try await DesignFlowCLICommand.runProcess(arguments: [
            "validate-retention-index",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "run-1",
        ])
        let validationData = try #require(validation.output.data(using: .utf8))
        let validationResult = try JSONDecoder().decode(
            FlowRunReleaseRetentionValidationResult.self,
            from: validationData
        )

        #expect(validation.exitCode == 0)
        #expect(validationResult.status == .passed)
        let manifest = try storage.loadRunManifest(runID: "run-1", inProjectAt: root)
        #expect(manifest.artifacts.contains { $0.artifactID == "qualification-retention-index" })
    }

    private func makeIndex(
        root: URL,
        previousEntryCount: Int = 0,
        retentionDays: Int = 30,
        minimumRetentionDays: Int = 30
    ) throws -> FlowRunReleaseRetentionIndex {
        let retentionDirectory = root.appending(path: "retention")
        try FileManager.default.createDirectory(at: retentionDirectory, withIntermediateDirectories: true)
        let timestamp = timestamp(Self.evaluationDate)
        try Data(#"{"runID":"run-1"}"#.utf8).write(
            to: retentionDirectory.appending(path: "dashboard.json"),
            options: .atomic
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
        try historyData.write(
            to: retentionDirectory.appending(path: "history.jsonl"),
            options: .atomic
        )

        return try DefaultFlowRunReleaseRetentionIndexBuilder().build(
            runID: "run-1",
            workflowRunID: "workflow-run-1",
            projectRoot: root,
            sourceDashboardPath: "retention/dashboard.json",
            historyPath: "retention/history.jsonl",
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
