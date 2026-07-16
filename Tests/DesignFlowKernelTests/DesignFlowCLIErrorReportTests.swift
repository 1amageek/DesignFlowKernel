import CircuiteFoundation
import Foundation
import Testing
@testable import DesignFlowKernel

@Test func flowRunNextActionRequiresSuggestedCommandsInCurrentSchema() throws {
    let payload = Data("""
    {"actionID":"repair","kind":"repair","severity":"error","reason":"Repair is required.","diagnosticCodes":[]}
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowRunNextAction.self, from: payload)
    }
}

@Test func flowRunManifestRequiresCanonicalArtifactReferences() throws {
    let payload = Data("""
    {"schemaVersion":1,"runID":"run-1","status":"created","actor":{"kind":"agent","identifier":"agent-1"},"intent":"verify","createdAt":"2026-07-14T00:00:00Z","updatedAt":"2026-07-14T00:00:00Z","revision":0}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    #expect(throws: DecodingError.self) {
        _ = try decoder.decode(FlowRunManifest.self, from: payload)
    }
}

@Test func flowRunLedgerRequiresCurrentSchemaFields() throws {
    let payload = Data("""
    {"schemaVersion":1,"runID":"run-1","runManifest":{},"stages":[]}
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowRunLedger.self, from: payload)
    }
}
