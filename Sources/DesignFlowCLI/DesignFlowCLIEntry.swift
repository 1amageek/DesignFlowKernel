import Darwin
import DesignFlowCLISupport
import Foundation

@main
struct DesignFlowCLIEntry {
    static func main() async {
        do {
            let result = try await DesignFlowCLICommand.runProcess(
                arguments: Array(CommandLine.arguments.dropFirst())
            ) { line in
                print(line)
            }
            if !result.output.isEmpty {
                print(result.output)
            }
            if result.exitCode != 0 {
                exit(Int32(result.exitCode))
            }
        } catch let error as DesignFlowCLIError {
            writeError(error.encodedReport())
            exit(Int32(error.exitCode))
        } catch {
            writeError(encodedUnexpectedErrorReport(error))
            exit(1)
        }
    }

    private static func encodedUnexpectedErrorReport(_ error: Error) -> String {
        let report = DesignFlowCLIErrorReport(
            exitCode: 1,
            diagnostic: DesignFlowCLIErrorDiagnostic(
                severity: "error",
                code: "design-flow.cli.unexpected-error",
                message: "Unexpected error: \(error.localizedDescription)",
                suggestedActions: [
                    "inspect-design-flow-cli-stack",
                    "report-design-flow-cli-unexpected-error"
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(report)
            guard let text = String(data: data, encoding: .utf8) else {
                return "Unexpected error: \(error.localizedDescription)"
            }
            return text
        } catch {
            return "Unexpected error: \(error.localizedDescription)"
        }
    }

    private static func writeError(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
