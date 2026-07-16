import CircuiteFoundation
import Foundation
import ToolQualification

enum TestToolQualificationFixtures {
    private struct EvidenceFixture: Sendable {
        let evidence: ToolEvidence
        let data: Data
    }

    private static let checkedAt = Date(timeIntervalSince1970: 1_784_000_000)

    static func qualificationRecord(
        for descriptor: ToolDescriptor,
        projectRoot: URL,
        corpusEvidenceID: String = "corpus-1"
    ) async throws -> ToolQualificationRecord {
        let issuer = try qualificationIssuer(toolID: descriptor.toolID)
        let smoke = try smokeFixture(toolID: descriptor.toolID, issuer: issuer)
        let corpus = try corpusFixture(
            toolID: descriptor.toolID,
            evidenceID: corpusEvidenceID,
            issuer: issuer
        )
        let health = try healthFixture(toolID: descriptor.toolID, issuer: issuer)
        let fixtures = [smoke, corpus, health]

        for fixture in fixtures {
            guard let artifact = fixture.evidence.artifact else {
                throw ToolQualificationRecordError.invalidStructure
            }
            let url = try artifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fixture.data.write(to: url, options: .atomic)
        }

        var qualifiedDescriptor = descriptor
        qualifiedDescriptor.trustProfile.level = .smokeChecked
        qualifiedDescriptor.trustProfile.evidence = [smoke.evidence]
        let healthResult = ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [health.evidence, corpus.evidence]
        )
        let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
        let record = try await DefaultToolQualificationRecordIssuer().issue(
            recordID: "\(descriptor.toolID)-test-qualification-record",
            descriptor: qualifiedDescriptor,
            health: healthResult,
            issuer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel-test-qualification",
                version: "1"
            ),
            reading: infrastructure,
            issuedAt: checkedAt
        )
        let recordURL = projectRoot.appending(
            path: ".xcircuite/qualification/test-fixtures/\(descriptor.toolID)-record.json"
        )
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try record.canonicalData().write(to: recordURL, options: .atomic)
        return record
    }

    private static func smokeFixture(
        toolID: String,
        issuer: ProducerIdentity
    ) throws -> EvidenceFixture {
        let result = ToolSmokeQualificationResult(
            resultID: "\(toolID)-smoke",
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            outputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "output",
                producer: issuer
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: result.resultID,
            toolID: toolID,
            kind: .smoke,
            data: result.canonicalData(),
            producer: issuer
        )
    }

    private static func corpusFixture(
        toolID: String,
        evidenceID: String,
        issuer: ProducerIdentity
    ) throws -> EvidenceFixture {
        let result = ToolCorpusQualificationResult(
            resultID: evidenceID,
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            scope: qualificationScope(toolID: toolID),
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            outputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "output",
                producer: issuer
            )],
            cases: [ToolQualificationCaseOutcome(
                caseID: "fixture-case",
                coverageTags: ["fixture"],
                comparisons: [ToolQualificationMetricComparison(
                    metricID: "pass",
                    observed: 1,
                    expected: 1
                )]
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: evidenceID,
            toolID: toolID,
            kind: .corpus,
            data: result.canonicalData(),
            producer: issuer
        )
    }

    private static func healthFixture(
        toolID: String,
        issuer: ProducerIdentity
    ) throws -> EvidenceFixture {
        let result = ToolHealthQualificationResult(
            resultID: "\(toolID)-health-check",
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            scope: qualificationScope(toolID: toolID),
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            outputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "health-output",
                producer: issuer
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: result.resultID,
            toolID: toolID,
            kind: .healthCheck,
            data: result.canonicalData(),
            producer: issuer
        )
    }

    private static func evidenceFixture(
        evidenceID: String,
        toolID: String,
        kind: ToolEvidenceKind,
        data: Data,
        producer: ProducerIdentity
    ) throws -> EvidenceFixture {
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "\(toolID)-\(kind.rawValue)-evidence"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/qualification/test-fixtures/\(toolID)-\(kind.rawValue).json"
                ),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: producer
        )
        return EvidenceFixture(
            evidence: ToolEvidence(
                evidenceID: evidenceID,
                kind: kind,
                artifact: artifact,
                checkedAt: checkedAt
            ),
            data: data
        )
    }

    private static func supportingArtifact(
        toolID: String,
        name: String,
        producer: ProducerIdentity
    ) throws -> ArtifactReference {
        let data = Data("\(toolID):\(name)".utf8)
        return ArtifactReference(
            id: try ArtifactID(rawValue: "\(toolID)-\(name)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/qualification/test-fixtures/\(toolID)-\(name).json"
                ),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: producer
        )
    }

    private static func qualificationIssuer(toolID: String) throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "\(toolID)-qualification-fixture",
            version: "1"
        )
    }

    private static func qualificationScope(toolID: String) -> ToolQualificationScope {
        ToolQualificationScope(
            implementationID: toolID,
            toolVersion: "1.0.0",
            binaryDigest: String(repeating: "1", count: 64),
            algorithmVersion: "fixture-v1",
            processProfileID: "fixture-process",
            processProfileDigest: String(repeating: "2", count: 64),
            deckDigest: String(repeating: "3", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "4", count: 64),
            oracle: ToolOracleQualificationScope(
                implementationID: "\(toolID)-oracle-tool",
                version: "1",
                binaryDigest: String(repeating: "5", count: 64)
            )
        )
    }
}
