import DesignFlowCLISupport
import Foundation
import Testing

@Test func designFlowCLIErrorReportIncludesStableDiagnosticFields() throws {
    let error = DesignFlowCLIError.invalidValue(
        option: "--timeout-milliseconds",
        value: "later",
        expected: "integer"
    )

    let report = error.report

    #expect(report.schemaVersion == 1)
    #expect(report.status == "failed")
    #expect(report.exitCode == 64)
    #expect(report.diagnostic.severity == "error")
    #expect(report.diagnostic.code == "design-flow.cli.invalid-value")
    #expect(report.diagnostic.option == "--timeout-milliseconds")
    #expect(report.diagnostic.value == "later")
    #expect(report.diagnostic.expected == "integer")
    #expect(report.diagnostic.suggestedActions.contains("provide-valid-value:--timeout-milliseconds"))
}

@Test func designFlowCLIErrorEncodedReportIsMachineReadableJSON() throws {
    let output = DesignFlowCLIError.missingOption("--project-root").encodedReport()
    let data = try #require(output.data(using: .utf8))
    let report = try JSONDecoder().decode(DesignFlowCLIErrorReport.self, from: data)

    #expect(report.status == "failed")
    #expect(report.exitCode == 64)
    #expect(report.diagnostic.code == "design-flow.cli.missing-option")
    #expect(report.diagnostic.option == "--project-root")
    #expect(report.diagnostic.suggestedActions.contains("provide-option:--project-root"))
}

@Test func designFlowCLICommandErrorsCanBeConvertedToReports() throws {
    do {
        _ = try DesignFlowCLICommand.run(arguments: [
            "progress-run",
            "--project-root",
            "/tmp/design-flow-test",
            "--run-id",
            "run-1",
            "--follow"
        ])
        Issue.record("Command should require runStreaming for follow mode.")
    } catch let error as DesignFlowCLIError {
        let report = error.report
        #expect(report.diagnostic.code == "design-flow.cli.invalid-value")
        #expect(report.diagnostic.option == "--follow")
        #expect(report.diagnostic.expected == "use runStreaming for follow mode")
    }
}
