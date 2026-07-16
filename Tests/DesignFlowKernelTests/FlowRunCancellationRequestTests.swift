import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("Flow run cancellation request")
struct FlowRunCancellationRequestTests {
    @Test func rejectsEmptyRequester() {
        #expect(throws: FlowRunCancellationRequestError.emptyRequestedBy) {
            _ = try FlowRunCancellationRequest(
                runID: "run-1",
                requestedBy: " \n ",
                reason: "Operator requested cancellation."
            )
        }
    }

    @Test func rejectsEmptyReason() {
        #expect(throws: FlowRunCancellationRequestError.emptyReason) {
            _ = try FlowRunCancellationRequest(
                runID: "run-1",
                requestedBy: "operator",
                reason: "\t"
            )
        }
    }

    @Test func decodingEnforcesTheSameValidation() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "requestedBy": "operator",
              "reason": "   ",
              "requestedAt": 0
            }
            """.utf8
        )
        #expect(throws: FlowRunCancellationRequestError.emptyReason) {
            _ = try JSONDecoder().decode(FlowRunCancellationRequest.self, from: data)
        }
    }
}
