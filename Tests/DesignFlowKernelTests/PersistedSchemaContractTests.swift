import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("Persisted flow schema contracts")
struct PersistedSchemaContractTests {
    @Test("schema version 1 records reject missing and unsupported versions")
    func version1RecordsFailClosed() throws {
        let value = FlowRunPlan(
            runID: "run-schema-v1",
            intent: "Verify strict schema decoding.",
            stages: []
        )

        try expectCurrentSchema(value)
    }

    @Test("schema version 3 records reject missing and unsupported versions")
    func version3RecordsFailClosed() throws {
        let value = FlowRunReviewBundle(
            runID: "run-schema-v2",
            status: .created,
            summary: FlowRunLedgerSummary(runID: "run-schema-v2", status: .created)
        )

        try expectCurrentSchema(value)
    }

    private func expectCurrentSchema<Value: Codable>(_ value: Value) throws {
        let encoded = try JSONEncoder().encode(value)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        object.removeValue(forKey: "schemaVersion")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Value.self, from: missing)
        }

        object["schemaVersion"] = 9_999
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Value.self, from: unsupported)
        }
    }
}
