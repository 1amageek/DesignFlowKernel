import Foundation

/// A signoff decision for one stage of one run, persisted at
/// `runs/{runID}/approvals/{stageID}.json`. One file per stage; a new
/// decision overwrites the old one — the ledger keeps the LATEST
/// verdict, and the run manifest's history shows what it gated.
///
/// Both sides of the loop speak this schema: the review cockpit writes
/// it, the flow kernel's approval gate reads it. `reviewerKind` records
/// WHO kind of actor decided (human, agent, cli, system) so an audited
/// ledger can always distinguish a human approval from an automated one.
public struct XcircuiteApprovalRecord: Sendable, Hashable, Codable {
    public enum Verdict: String, Sendable, Hashable, Codable {
        case approved
        case rejected
    }

    public var runID: String
    public var stageID: String
    public var verdict: Verdict
    public var reviewer: String
    public var reviewerKind: XcircuiteRunActionActor.Kind
    public var note: String
    public var createdAt: Date
    public var planSHA256: String?
    public var planByteCount: Int64?
    public var stageResultSHA256: String?
    public var stageResultByteCount: Int64?

    public init(
        runID: String,
        stageID: String,
        verdict: Verdict,
        reviewer: String,
        reviewerKind: XcircuiteRunActionActor.Kind = .human,
        note: String = "",
        createdAt: Date = Date(),
        planSHA256: String? = nil,
        planByteCount: Int64? = nil,
        stageResultSHA256: String? = nil,
        stageResultByteCount: Int64? = nil
    ) {
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.createdAt = createdAt
        self.planSHA256 = planSHA256
        self.planByteCount = planByteCount
        self.stageResultSHA256 = stageResultSHA256
        self.stageResultByteCount = stageResultByteCount
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case stageID
        case verdict
        case reviewer
        case reviewerKind
        case note
        case createdAt
        case planSHA256
        case planByteCount
        case stageResultSHA256
        case stageResultByteCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        stageID = try container.decode(String.self, forKey: .stageID)
        verdict = try container.decode(Verdict.self, forKey: .verdict)
        reviewer = try container.decode(String.self, forKey: .reviewer)
        reviewerKind = try container.decode(
            XcircuiteRunActionActor.Kind.self,
            forKey: .reviewerKind
        )
        note = try container.decode(String.self, forKey: .note)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        planSHA256 = try container.decodeIfPresent(String.self, forKey: .planSHA256)
        planByteCount = try container.decodeIfPresent(Int64.self, forKey: .planByteCount)
        stageResultSHA256 = try container.decodeIfPresent(String.self, forKey: .stageResultSHA256)
        stageResultByteCount = try container.decodeIfPresent(Int64.self, forKey: .stageResultByteCount)
    }
}

extension XcircuitePackageStore {
    @discardableResult
    public func recordApprovalAction(
        _ record: XcircuiteApprovalRecord,
        actionID: String? = nil,
        metadata: [String: XcircuiteJSONValue] = [:],
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        var record = record
        try bindApprovalIfPossible(&record, inProjectAt: projectRoot)
        try validateApprovalIdentifiers(record.runID, stageID: record.stageID)
        let approvalReference = try writeApprovalArtifact(record, inProjectAt: projectRoot)
        let approvalPath = approvalReference.path
        let foundationApprovalReference = try approvalReference.foundationArtifactReference(role: .output)

        return try appendReviewDecisionAction(
            XcircuiteRunReviewDecisionActionRequest(
                actionID: actionID ?? "approval-\(record.stageID)-\(UUID().uuidString)",
                runID: record.runID,
                stageID: record.stageID,
                actor: XcircuiteRunActionActor(kind: record.reviewerKind, identifier: record.reviewer),
                decisionKind: .approval,
                decision: record.verdict.rawValue,
                targetID: record.stageID,
                targetPath: approvalPath,
                reason: record.note,
                outputs: [foundationApprovalReference],
                diagnostics: [
                    XcircuiteRunActionDiagnostic(
                        severity: record.verdict == .approved ? .info : .warning,
                        code: record.verdict == .approved ? "approval-decision-approved" : "approval-decision-rejected",
                        message: "Recorded \(record.verdict.rawValue) approval decision for \(record.stageID)."
                    ),
                ],
                metadata: approvalActionMetadata(record: record, path: approvalPath, metadata: metadata),
                createdAt: record.createdAt
            ),
            inProjectAt: projectRoot
        )
    }

    @discardableResult
    public func writeApprovalArtifact(
        _ record: XcircuiteApprovalRecord,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        var record = record
        try bindApprovalIfPossible(&record, inProjectAt: projectRoot)
        try validateApprovalIdentifiers(record.runID, stageID: record.stageID)
        try persistApprovalRecord(record, inProjectAt: projectRoot)

        let approvalPath = "\(XcircuitePackage.directoryName)/runs/\(record.runID)/approvals/\(record.stageID).json"
        let approvalReference = try fileReference(
            forProjectRelativePath: approvalPath,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: record.runID
        )
        try upsertRunArtifact(approvalReference, runID: record.runID, inProjectAt: projectRoot)
        return approvalReference
    }

    /// Persists and audits `record` as the stage's current decision.
    public func writeApproval(
        _ record: XcircuiteApprovalRecord,
        inProjectAt projectRoot: URL
    ) throws {
        _ = try recordApprovalAction(
            record,
            metadata: [
                "source": .string("xcircuite-package.write-approval"),
            ],
            inProjectAt: projectRoot
        )
    }

    private func persistApprovalRecord(
        _ record: XcircuiteApprovalRecord,
        inProjectAt projectRoot: URL
    ) throws {
        var record = record
        try bindApprovalIfPossible(&record, inProjectAt: projectRoot)
        try validateApprovalIdentifiers(record.runID, stageID: record.stageID)
        let package = XcircuitePackage(projectRoot: projectRoot)
        let directory = try package.runDirectoryURL(for: record.runID)
            .appending(path: "approvals")
        try ensureDirectory(at: directory)
        try writeJSON(
            record,
            to: directory.appending(path: "\(record.stageID).json"),
            forProjectAt: projectRoot
        )
    }

    private func bindApprovalIfPossible(
        _ record: inout XcircuiteApprovalRecord,
        inProjectAt projectRoot: URL
    ) throws {
        try validateApprovalIdentifiers(record.runID, stageID: record.stageID)
        let package = XcircuitePackage(projectRoot: projectRoot)
        let runDirectory = try package.runDirectoryURL(for: record.runID)
        if record.planSHA256 == nil || record.planByteCount == nil {
            let planURL = runDirectory.appending(path: "plan.json")
            if fileExists(planURL) {
                record.planSHA256 = try XcircuiteHasher().sha256(fileAt: planURL)
                record.planByteCount = try XcircuiteHasher().byteCount(fileAt: planURL)
            }
        }
        if record.stageResultSHA256 == nil || record.stageResultByteCount == nil {
            let resultURL = runDirectory
                .appending(path: "stages")
                .appending(path: record.stageID)
                .appending(path: "result.json")
            if fileExists(resultURL) {
                record.stageResultSHA256 = try XcircuiteHasher().sha256(fileAt: resultURL)
                record.stageResultByteCount = try XcircuiteHasher().byteCount(fileAt: resultURL)
            }
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    /// The stage's current decision, or nil when no human has decided.
    public func loadApproval(
        runID: String,
        stageID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteApprovalRecord? {
        try validateApprovalIdentifiers(runID, stageID: stageID)
        let package = XcircuitePackage(projectRoot: projectRoot)
        let url = try package.runDirectoryURL(for: runID)
            .appending(path: "approvals")
            .appending(path: "\(stageID).json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(XcircuiteApprovalRecord.self, from: data)
        } catch {
            throw XcircuitePackageError.decodeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    /// Every stage decision recorded for the run, sorted by stage ID.
    public func loadApprovals(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteApprovalRecord] {
        let package = XcircuitePackage(projectRoot: projectRoot)
        let directory = try package.runDirectoryURL(for: runID)
            .appending(path: "approvals")
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw XcircuitePackageError.readFailed(
                "approvals: \(error.localizedDescription)"
            )
        }
        var records: [XcircuiteApprovalRecord] = []
        for url in contents where url.pathExtension == "json" {
            let stageID = url.deletingPathExtension().lastPathComponent
            try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
            if let record = try loadApproval(
                runID: runID,
                stageID: stageID,
                inProjectAt: projectRoot
            ) {
                records.append(record)
            }
        }
        return records.sorted { $0.stageID < $1.stageID }
    }

    private func approvalActionMetadata(
        record: XcircuiteApprovalRecord,
        path: String,
        metadata: [String: XcircuiteJSONValue]
    ) -> [String: XcircuiteJSONValue] {
        var result = metadata
        result["approvalPath"] = .string(path)
        result["verdict"] = .string(record.verdict.rawValue)
        result["reviewer"] = .string(record.reviewer)
        result["reviewerKind"] = .string(record.reviewerKind.rawValue)
        result["note"] = .string(record.note)
        return result
    }

    private func validateApprovalIdentifiers(_ runID: String, stageID: String) throws {
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(runID, kind: .runID)
        try validator.validate(stageID, kind: .stageID)
    }
}
