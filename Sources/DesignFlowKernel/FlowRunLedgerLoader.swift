import Foundation

public struct FlowRunLedgerLoader: FlowRunLedgerLoading {
    private let storage: any FlowExecutionStorage
    private let progressStore: FlowRunProgressStore

    public init(
        storage: any FlowExecutionStorage,
        progressStore: FlowRunProgressStore? = nil
    ) {
        self.storage = storage
        self.progressStore = progressStore ?? FlowRunProgressStore(packageStore: storage)
    }

    @available(*, deprecated, message: "Inject a FlowExecutionStorage implementation.")
    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        progressStore: FlowRunProgressStore = FlowRunProgressStore()
    ) {
        self.init(storage: packageStore, progressStore: progressStore)
    }

    public func loadRunLedger(runID: String, projectRoot: URL) throws -> FlowRunLedger {
        let runDirectory = try storage.runDirectory(
            for: runID,
            inProjectAt: projectRoot
        )
        let runManifest = try storage.loadRunManifest(
            runID: runID,
            inProjectAt: projectRoot
        )
        let plan = try loadPlan(from: runDirectory)
        let stages = try loadStageResults(
            from: runDirectory,
            plan: plan,
            runStatus: runManifest.status
        )
        let toolchain = try loadToolchain(from: runDirectory)
        let designDiff = try loadDesignDiff(from: runDirectory)
        let progressEvents = try progressStore.loadProgressEvents(
            runID: runID,
            projectRoot: projectRoot
        )
        let cancellationRequest = try progressStore.loadCancellationRequest(
            runID: runID,
            projectRoot: projectRoot
        )
        let actions = try storage.loadRunActions(
            runID: runID,
            inProjectAt: projectRoot
        )
        let suggestedCommandSelections = try storage.loadSuggestedCommandSelections(
            runID: runID,
            inProjectAt: projectRoot
        )
        let approvals = try storage.loadApprovals(
            runID: runID,
            inProjectAt: projectRoot
        )
        return FlowRunLedger(
            runID: runID,
            runDirectory: runDirectory,
            runManifest: runManifest,
            plan: plan,
            stages: stages,
            toolchain: toolchain,
            designDiff: designDiff,
            progressEvents: progressEvents,
            cancellationRequest: cancellationRequest,
            actions: actions,
            suggestedCommandSelections: suggestedCommandSelections,
            approvals: approvals
        )
    }

    private func loadStageResults(
        from runDirectory: URL,
        plan: FlowRunPlan?,
        runStatus: XcircuiteRunStatus
    ) throws -> [FlowStageResult] {
        let stagesDirectory = runDirectory.appending(path: "stages")
        guard directoryExists(stagesDirectory) else {
            if stageResultCompleteness(runStatus) == .complete,
               let plannedStageIDs = plan?.stages.map(\.stageID),
               !plannedStageIDs.isEmpty {
                throw XcircuitePackageError.readFailed(
                    "stages directory missing for planned stages: \(plannedStageIDs.sorted().joined(separator: ", "))"
                )
            }
            return []
        }

        let stageDirectories: [URL]
        do {
            stageDirectories = try FileManager.default.contentsOfDirectory(
                at: stagesDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            throw XcircuitePackageError.readFailed(
                "stages: \(error.localizedDescription)"
            )
        }

        var results: [FlowStageResult] = []
        var resultDirectoryStageIDs: [String] = []
        for stageDirectory in stageDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard directoryExists(stageDirectory) else {
                continue
            }
            let resultURL = stageDirectory.appending(path: "result.json")
            guard fileExists(resultURL) else {
                throw XcircuitePackageError.readFailed(
                    "stage result missing: stages/\(stageDirectory.lastPathComponent)/result.json"
                )
            }
            let result = try storage.readJSON(FlowStageResult.self, from: resultURL)
            results.append(result)
            resultDirectoryStageIDs.append(stageDirectory.lastPathComponent)
        }
        if let plan {
            let plannedStageIDs = plan.stages.map(\.stageID)
            let loadedStageIDs = Set(resultDirectoryStageIDs)
            switch stageResultCompleteness(runStatus) {
            case .complete:
                let missingStageIDs = plannedStageIDs.filter { !loadedStageIDs.contains($0) }
                if !missingStageIDs.isEmpty {
                    throw XcircuitePackageError.readFailed(
                        "stage results missing for planned stages: \(missingStageIDs.sorted().joined(separator: ", "))"
                    )
                }
            case .plannedPrefix:
                // The orchestrator stops at the first blocked/failed stage
                // and never records results for the stages it did not
                // reach, so an interrupted run legitimately holds results
                // for only a leading slice of the plan. What must never
                // happen is a GAP: a planned stage without a result that
                // is followed by one with a result means evidence was
                // lost, not that the run stopped early.
                let loadedPlannedStageIDs = loadedStageIDs.intersection(plannedStageIDs)
                let executedPrefix = plannedStageIDs.prefix { loadedPlannedStageIDs.contains($0) }
                let gapStageIDs = loadedPlannedStageIDs.subtracting(executedPrefix)
                if !gapStageIDs.isEmpty {
                    throw XcircuitePackageError.readFailed(
                        "stage results skip earlier planned stages: \(gapStageIDs.sorted().joined(separator: ", "))"
                    )
                }
            case .notRequired:
                break
            }
        }
        return results
    }

    private enum StageResultCompleteness {
        case complete
        case plannedPrefix
        case notRequired
    }

    private func stageResultCompleteness(_ status: XcircuiteRunStatus) -> StageResultCompleteness {
        switch status {
        case .created, .running:
            .notRequired
        case .succeeded:
            .complete
        case .failed, .cancelled, .blocked, .partial:
            .plannedPrefix
        }
    }

    private func loadPlan(from runDirectory: URL) throws -> FlowRunPlan? {
        let planURL = runDirectory.appending(path: "plan.json")
        guard fileExists(planURL) else {
            return nil
        }
        return try storage.readJSON(FlowRunPlan.self, from: planURL)
    }

    private func loadToolchain(from runDirectory: URL) throws -> FlowToolchainManifest? {
        let toolchainURL = runDirectory.appending(path: "toolchain.json")
        guard fileExists(toolchainURL) else {
            return nil
        }
        return try storage.readJSON(FlowToolchainManifest.self, from: toolchainURL)
    }

    private func loadDesignDiff(from runDirectory: URL) throws -> XcircuiteDesignDiff? {
        let designDiffURL = runDirectory.appending(path: "design-diff.json")
        guard fileExists(designDiffURL) else {
            return nil
        }
        return try storage.readJSON(XcircuiteDesignDiff.self, from: designDiffURL)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}
