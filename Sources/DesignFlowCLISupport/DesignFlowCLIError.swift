import Foundation

public enum DesignFlowCLIError: Error {
    case usage
    case unknownCommand(String)
    case unknownOption(String)
    case invalidValue(option: String, value: String, expected: String)
    case missingOption(String)
    case missingValue(String)
    case encodeFailed(String)

    public var exitCode: Int {
        switch self {
        case .usage, .unknownCommand, .unknownOption, .invalidValue, .missingOption, .missingValue:
            return 64
        case .encodeFailed:
            return 1
        }
    }

    public var message: String {
        switch self {
        case .usage:
            return DesignFlowCLICommand.runUsageMessage
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .invalidValue(let option, let value, let expected):
            return "Invalid value for \(option): \(value). Expected \(expected)."
        case .missingOption(let option):
            return "Missing required option: \(option)"
        case .missingValue(let option):
            return "Missing value after option: \(option)"
        case .encodeFailed(let reason):
            return "Failed to encode output: \(reason)"
        }
    }

    public var diagnostic: DesignFlowCLIErrorDiagnostic {
        switch self {
        case .usage:
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.usage",
                message: message,
                suggestedActions: [
                    "run-design-flow-help",
                    "choose-supported-command"
                ]
            )
        case .unknownCommand(let command):
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.unknown-command",
                message: message,
                value: command,
                expected: "supported design-flow command",
                suggestedActions: [
                    "run-design-flow-help",
                    "choose-supported-command"
                ]
            )
        case .unknownOption(let option):
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.unknown-option",
                message: message,
                option: option,
                expected: "supported option for the selected command",
                suggestedActions: [
                    "check-command-help",
                    "remove-unknown-option"
                ]
            )
        case .invalidValue(let option, let value, let expected):
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.invalid-value",
                message: message,
                option: option,
                value: value,
                expected: expected,
                suggestedActions: [
                    "provide-valid-value:\(option)",
                    "check-command-help"
                ]
            )
        case .missingOption(let option):
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.missing-option",
                message: message,
                option: option,
                expected: "required option",
                suggestedActions: [
                    "provide-option:\(option)",
                    "check-command-help"
                ]
            )
        case .missingValue(let option):
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.missing-value",
                message: message,
                option: option,
                expected: "option value",
                suggestedActions: [
                    "provide-value:\(option)",
                    "check-command-help"
                ]
            )
        case .encodeFailed:
            return DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.encode-failed",
                message: message,
                expected: "Codable JSON output",
                suggestedActions: [
                    "inspect-output-model-codable-conformance",
                    "report-design-flow-cli-encoding-failure"
                ]
            )
        }
    }

    public var report: DesignFlowCLIErrorReport {
        DesignFlowCLIErrorReport(exitCode: exitCode, diagnostic: diagnostic)
    }

    public func encodedReport(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        do {
            let data = try encoder.encode(report)
            guard let text = String(data: data, encoding: .utf8) else {
                return message
            }
            return text
        } catch {
            return message
        }
    }
}

public struct DesignFlowCLIExecutionResult: Sendable, Hashable {
    public var output: String
    public var exitCode: Int

    public init(output: String, exitCode: Int = 0) {
        self.output = output
        self.exitCode = exitCode
    }
}

extension DesignFlowCLICommand {
    static var runUsageMessage: String {
        "Usage: design-flow approve-gate ... | design-flow inspect-run ... | design-flow review-run ... | design-flow summarize-loop ... | design-flow evaluate-run-guard ... | design-flow compare-artifacts ... | design-flow progress-run ..."
    }
}
