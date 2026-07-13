import Foundation

public struct FlowRunReleaseCorpusHistory: Sendable, Hashable, Codable {
    public struct DomainSummary: Sendable, Hashable, Codable {
        public var domain: String
        public var status: String?
        public var previousQualifiedEntryCount: Int
        public var currentStatus: String?
        public var qualified: Bool?
        public var caseCount: Double?
        public var passRate: Double?
        public var totalDurationSeconds: Double?
        public var coverageTagCount: Double?
        public var failureCount: Int

        public init(
            domain: String,
            status: String?,
            previousQualifiedEntryCount: Int,
            currentStatus: String?,
            qualified: Bool?,
            caseCount: Double?,
            passRate: Double?,
            totalDurationSeconds: Double?,
            coverageTagCount: Double?,
            failureCount: Int
        ) {
            self.domain = domain
            self.status = status
            self.previousQualifiedEntryCount = previousQualifiedEntryCount
            self.currentStatus = currentStatus
            self.qualified = qualified
            self.caseCount = caseCount
            self.passRate = passRate
            self.totalDurationSeconds = totalDurationSeconds
            self.coverageTagCount = coverageTagCount
            self.failureCount = failureCount
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var collectedAt: String
    public var sourceDashboardPath: String
    public var sourceDashboardSHA256: String
    public var sourceRecordedAt: String?
    public var dashboardStatus: String?
    public var historyStatus: String?
    public var previousEntryCount: Int
    public var appended: Bool?
    public var retainedSignoffSuiteStatus: String?
    public var domains: [DomainSummary]
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        collectedAt: String,
        sourceDashboardPath: String,
        sourceDashboardSHA256: String,
        sourceRecordedAt: String? = nil,
        dashboardStatus: String?,
        historyStatus: String?,
        previousEntryCount: Int,
        appended: Bool?,
        retainedSignoffSuiteStatus: String?,
        domains: [DomainSummary],
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.collectedAt = collectedAt
        self.sourceDashboardPath = sourceDashboardPath
        self.sourceDashboardSHA256 = sourceDashboardSHA256
        self.sourceRecordedAt = sourceRecordedAt
        self.dashboardStatus = dashboardStatus
        self.historyStatus = historyStatus
        self.previousEntryCount = previousEntryCount
        self.appended = appended
        self.retainedSignoffSuiteStatus = retainedSignoffSuiteStatus
        self.domains = domains
        self.diagnostics = diagnostics
    }
}

public struct FlowRunReleasePerformanceEnvelope: Sendable, Hashable, Codable {
    public struct DomainEnvelope: Sendable, Hashable, Codable {
        public var domain: String
        public var status: String?
        public var currentTotalDurationSeconds: Double?
        public var medianTotalDurationSeconds: Double?
        public var maxAllowedTotalDurationSeconds: Double?
        public var durationRegressionRatio: Double?
        public var currentPassRate: Double?
        public var medianPassRate: Double?
        public var failureCount: Int

        public init(
            domain: String,
            status: String?,
            currentTotalDurationSeconds: Double?,
            medianTotalDurationSeconds: Double?,
            maxAllowedTotalDurationSeconds: Double?,
            durationRegressionRatio: Double?,
            currentPassRate: Double?,
            medianPassRate: Double?,
            failureCount: Int
        ) {
            self.domain = domain
            self.status = status
            self.currentTotalDurationSeconds = currentTotalDurationSeconds
            self.medianTotalDurationSeconds = medianTotalDurationSeconds
            self.maxAllowedTotalDurationSeconds = maxAllowedTotalDurationSeconds
            self.durationRegressionRatio = durationRegressionRatio
            self.currentPassRate = currentPassRate
            self.medianPassRate = medianPassRate
            self.failureCount = failureCount
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var collectedAt: String
    public var sourceDashboardPath: String
    public var sourceDashboardSHA256: String
    public var sourceRecordedAt: String?
    public var historyStatus: String?
    public var maxTotalDurationRegression: Double?
    public var domains: [DomainEnvelope]
    public var promotionStatus: String?
    public var promotionFailureCount: Int
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        collectedAt: String,
        sourceDashboardPath: String,
        sourceDashboardSHA256: String,
        sourceRecordedAt: String? = nil,
        historyStatus: String?,
        maxTotalDurationRegression: Double?,
        domains: [DomainEnvelope],
        promotionStatus: String?,
        promotionFailureCount: Int,
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.collectedAt = collectedAt
        self.sourceDashboardPath = sourceDashboardPath
        self.sourceDashboardSHA256 = sourceDashboardSHA256
        self.sourceRecordedAt = sourceRecordedAt
        self.historyStatus = historyStatus
        self.maxTotalDurationRegression = maxTotalDurationRegression
        self.domains = domains
        self.promotionStatus = promotionStatus
        self.promotionFailureCount = promotionFailureCount
        self.diagnostics = diagnostics
    }
}

public struct FlowRunReleaseContractAudit: Sendable, Hashable, Codable {
    public struct ContractSummary: Sendable, Hashable, Codable {
        public var contractID: String
        public var owner: String
        public var status: String
        public var expectedVersion: XcircuiteJSONValue
        public var observedVersion: XcircuiteJSONValue
        public var requiredPathCount: Int
        public var failureCount: Int

        public init(
            contractID: String,
            owner: String,
            status: String,
            expectedVersion: XcircuiteJSONValue,
            observedVersion: XcircuiteJSONValue,
            requiredPathCount: Int,
            failureCount: Int
        ) {
            self.contractID = contractID
            self.owner = owner
            self.status = status
            self.expectedVersion = expectedVersion
            self.observedVersion = observedVersion
            self.requiredPathCount = requiredPathCount
            self.failureCount = failureCount
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var collectedAt: String
    public var sourceReportPath: String
    public var sourceReportSHA256: String
    public var status: String
    public var contractCount: Int
    public var failedContractCount: Int
    public var contracts: [ContractSummary]
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        collectedAt: String,
        sourceReportPath: String,
        sourceReportSHA256: String,
        status: String,
        contractCount: Int,
        failedContractCount: Int,
        contracts: [ContractSummary],
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.collectedAt = collectedAt
        self.sourceReportPath = sourceReportPath
        self.sourceReportSHA256 = sourceReportSHA256
        self.status = status
        self.contractCount = contractCount
        self.failedContractCount = failedContractCount
        self.contracts = contracts
        self.diagnostics = diagnostics
    }
}
