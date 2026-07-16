import Foundation

public struct FlowRunContractReport: Sendable, Hashable, Decodable {
    public struct Failure: Sendable, Hashable, Decodable {}

    public struct Contract: Sendable, Hashable, Decodable {
        public var id: String
        public var owner: String
        public var status: String
        public var expectedVersion: FlowContractVersion
        public var observedVersion: FlowContractVersion
        public var requiredPathCount: Int
        public var failures: [Failure]
    }

    @FlowSchemaVersion1 public var schemaVersion: Int
    public var status: String
    public var contractCount: Int
    public var failedContractCount: Int
    public var contracts: [Contract]
}
