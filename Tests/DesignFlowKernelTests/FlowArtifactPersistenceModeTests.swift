import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("Flow artifact persistence mode")
struct FlowArtifactPersistenceModeTests {
    @Test
    func createOnlyIsDistinctAndCodable() throws {
        let mode = FlowArtifactPersistenceMode.createOnly
        let encoded = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(
            FlowArtifactPersistenceMode.self,
            from: encoded
        )

        #expect(decoded == .createOnly)
        #expect(decoded != .immutable)
        #expect(decoded != .replaceable)
    }
}
