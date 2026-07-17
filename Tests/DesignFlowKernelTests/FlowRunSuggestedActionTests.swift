import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing

@Suite("Flow run suggested action")
struct FlowRunSuggestedActionTests {
    @Test("semantic action round-trips without composition details")
    func semanticActionRoundTripsWithoutCompositionDetails() throws {
        let action = FlowRunSuggestedAction(
            id: "generate-candidate-plan.with-rejected-feedback",
            readiness: .ready,
            operation: .generateCandidatePlan(
                rejectedPlansArtifactID: try ArtifactID(rawValue: "planning-rejected-plans")
            ),
            runID: "run-1",
            reason: "Regenerate the candidate plan from retained feedback."
        )

        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(FlowRunSuggestedAction.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        #expect(decoded == action)
        #expect(!json.contains("executable"))
        #expect(!json.contains("arguments"))
        #expect(!json.contains("workspace"))
    }

    @Test("action can require a run identifier before projection")
    func actionCanRequireRunIdentifierBeforeProjection() throws {
        let action = FlowRunSuggestedAction(
            id: "review-run",
            readiness: .requiresInput,
            operation: .reviewRun,
            runID: nil,
            reason: "Select a valid run before review."
        )

        let decoded = try JSONDecoder().decode(
            FlowRunSuggestedAction.self,
            from: JSONEncoder().encode(action)
        )

        #expect(decoded.readiness == .requiresInput)
        #expect(decoded.runID == nil)
    }
}
