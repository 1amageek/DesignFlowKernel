import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import XcircuitePackage

extension FlowRunLedgerSummaryTests {
@Test func reviewBundlerCreatesHumanAndAgentReviewContract() async throws {
    let root = try makeTemporaryRoot("agent-review-bundle")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)

    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )
    try XcircuitePackageStore().writeDesignDiff(
        XcircuiteDesignDiff(
            runID: "run-1",
            title: "DRC repair proposal",
            actor: "agent-1",
            changes: [
                XcircuiteDesignDiffChange(
                    changeID: "change-1",
                    domain: .layout,
                    operation: .replace,
                    path: "/cells/INV/layout/shapes/met1/rail",
                    before: .object(["width": .number(0.14)]),
                    after: .object(["width": .number(0.20)]),
                    summary: "Widen the met1 rail before approval."
                ),
            ]
        ),
        inProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    #expect(bundle.schemaVersion == 1)
    #expect(bundle.runID == "run-1")
    #expect(bundle.status == .blocked)
    #expect(bundle.summary.nextActions.map(\.kind).contains("reviewDesignDiff"))
    #expect(bundle.reviewItems.contains {
        $0.kind == .designDiff
            && $0.status == .needsReview
            && $0.artifactPaths == [".xcircuite/runs/run-1/design-diff.json"]
    })
    #expect(bundle.reviewItems.contains {
        $0.kind == .approvalGate
            && $0.status == .needsReview
            && $0.stageID == "001-drc"
            && $0.diagnosticCodes.contains("APPROVAL_PENDING")
            && $0.artifactPaths.contains(".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json")
    })
    #expect(bundle.artifacts.contains {
        $0.role == "toolchain" && $0.path == ".xcircuite/runs/run-1/toolchain.json"
    })
    #expect(bundle.artifacts.contains {
        $0.role == "stage-result"
            && $0.stageID == "001-drc"
            && $0.path == ".xcircuite/runs/run-1/stages/001-drc/result.json"
    })
    let summaryArtifact = try #require(bundle.artifacts.first {
        $0.role == "stage-summary"
            && $0.artifactID == "drc-summary"
            && $0.stageID == "001-drc"
            && $0.path == summaryPath
    })
    let expectedSummaryDigest = XcircuiteHasher().sha256(data: summaryPayload)
    #expect(summaryArtifact.sha256 == expectedSummaryDigest)
    #expect(summaryArtifact.byteCount == Int64(summaryPayload.count))
    #expect(summaryArtifact.integrity?.status == .verified)
    #expect(summaryArtifact.integrity?.expectedSHA256 == expectedSummaryDigest)
    #expect(summaryArtifact.integrity?.actualSHA256 == expectedSummaryDigest)
    #expect(summaryArtifact.integrity?.expectedByteCount == Int64(summaryPayload.count))
    #expect(summaryArtifact.integrity?.actualByteCount == Int64(summaryPayload.count))
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "diff"
            && $0.path == ".xcircuite/runs/run-1/design-diff.json"
            && $0.reviewItemIDs == ["review-design-diff"]
    } == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "drc"
            && $0.path == summaryPath
            && $0.reviewItemIDs.contains("001-drc-decide-approval")
    } == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "integrity"
            && $0.path == summaryPath
            && $0.integrityStatus == .verified
    } == true)
}

@Test func reviewBundlerIncludesRunManifestPlanningArtifacts() async throws {
    let root = try makeTemporaryRoot("agent-review-planning-artifact")
    defer { removeTemporaryRoot(root) }
    let planningPath = ".xcircuite/runs/run-1/planning/action-domain-snapshot.json"
    let planningPayload = Data(#"{"schemaVersion":1,"domains":[]}"#.utf8)
    let problemPath = ".xcircuite/runs/run-1/planning/problem.json"
    let problemPayload = Data(#"{"schemaVersion":1,"problemID":"problem-1"}"#.utf8)
    let problemTranslationAuditPath = ".xcircuite/runs/run-1/planning/problem-translation-audit.json"
    let problemTranslationAuditPayload = Data(#"{"schemaVersion":1,"status":"passed","problemID":"problem-1"}"#.utf8)
    let candidatePlanPath = ".xcircuite/runs/run-1/planning/candidate-plan.json"
    let candidatePlanPayload = Data(#"{"schemaVersion":1,"planID":"plan-1"}"#.utf8)
    let symbolicPlannerTracePath = ".xcircuite/runs/run-1/planning/symbolic-planner-trace.json"
    let symbolicPlannerTracePayload = Data(#"{"schemaVersion":1,"generatedPlanID":"plan-1"}"#.utf8)
    let parameterCandidatesPath = ".xcircuite/runs/run-1/planning/parameter-candidates.jsonl"
    let parameterCandidatesPayload = Data(#"{"schemaVersion":1,"candidateID":"candidate-1"}"#.utf8)
    let searchTracePath = ".xcircuite/runs/run-1/planning/parameter-candidate-search-trace.json"
    let searchTracePayload = Data(#"{"schemaVersion":1,"strategy":"adaptive-bounded-refinement"}"#.utf8)
    let selectionTracePath = ".xcircuite/runs/run-1/planning/parameter-candidate-selection-trace.json"
    let selectionTracePayload = Data(#"{"schemaVersion":1,"selectedCandidateID":"candidate-1"}"#.utf8)
    let planVerificationPath = ".xcircuite/runs/run-1/planning/plan-verification.json"
    let planVerificationPayload = Data("""
    {"schemaVersion":1,"planID":"plan-1","accepted":false,"correctnessGateResults":[{"gateID":"action-domain-binding","status":"passed","summary":"Candidate steps bind to declared action-domain operations."},{"gateID":"problem-translation-audit","status":"blocked","summary":"Planning problem translation audit must run before planner execution.","diagnostics":[{"code":"problem-translation-audit-required"}],"nextActions":["audit-problem-translation"]},{"gateID":"post-execution-signoff","status":"pending","summary":"Post-execution signoff gates still need to run.","diagnostics":[{"code":"post-execution-verification-required"}],"nextActions":["verify-candidate-plan:post-execution"]}]}
    """.utf8)
    let rejectedPlansPath = ".xcircuite/runs/run-1/planning/rejected-plans.jsonl"
    let rejectedPlansPayload = Data(#"{"schemaVersion":1,"rejectionID":"rejection-1","status":"rejected"}"#.utf8)
    let planExecutionPath = ".xcircuite/runs/run-1/planning/plan-execution.json"
    let planExecutionPayload = Data(#"{"schemaVersion":1,"planID":"plan-1","status":"executed"}"#.utf8)
    let editedNetlistPath = ".xcircuite/runs/run-1/planning/executions/plan-1/step-1/netlist.spice"
    let editedNetlistPayload = Data("RC\nr1 in out r=1.5k\n.end\n".utf8)
    let editReportPath = ".xcircuite/runs/run-1/planning/executions/plan-1/step-1/netlist-parameter-edit-report.json"
    let editReportPayload = Data(#"{"schemaVersion":1,"stepID":"step-1","edits":[]}"#.utf8)

    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let store = XcircuitePackageStore()
    try FileManager.default.createDirectory(
        at: root.appending(path: planningPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try planningPayload.write(to: root.appending(path: planningPath), options: .atomic)
    try problemPayload.write(to: root.appending(path: problemPath), options: .atomic)
    try problemTranslationAuditPayload.write(to: root.appending(path: problemTranslationAuditPath), options: .atomic)
    try candidatePlanPayload.write(to: root.appending(path: candidatePlanPath), options: .atomic)
    try symbolicPlannerTracePayload.write(to: root.appending(path: symbolicPlannerTracePath), options: .atomic)
    try parameterCandidatesPayload.write(to: root.appending(path: parameterCandidatesPath), options: .atomic)
    try searchTracePayload.write(to: root.appending(path: searchTracePath), options: .atomic)
    try selectionTracePayload.write(to: root.appending(path: selectionTracePath), options: .atomic)
    try planVerificationPayload.write(to: root.appending(path: planVerificationPath), options: .atomic)
    try rejectedPlansPayload.write(to: root.appending(path: rejectedPlansPath), options: .atomic)
    try planExecutionPayload.write(to: root.appending(path: planExecutionPath), options: .atomic)
    try FileManager.default.createDirectory(
        at: root.appending(path: editedNetlistPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try editedNetlistPayload.write(to: root.appending(path: editedNetlistPath), options: .atomic)
    try editReportPayload.write(to: root.appending(path: editReportPath), options: .atomic)
    let reference = try store.fileReference(
        forProjectRelativePath: planningPath,
        artifactID: "planning-action-domain-snapshot",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(reference, runID: "run-1", inProjectAt: root)
    let problemReference = try store.fileReference(
        forProjectRelativePath: problemPath,
        artifactID: "planning-problem",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(problemReference, runID: "run-1", inProjectAt: root)
    let problemTranslationAuditReference = try store.fileReference(
        forProjectRelativePath: problemTranslationAuditPath,
        artifactID: "planning-problem-translation-audit",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(problemTranslationAuditReference, runID: "run-1", inProjectAt: root)
    let candidatePlanReference = try store.fileReference(
        forProjectRelativePath: candidatePlanPath,
        artifactID: "planning-candidate-plan",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(candidatePlanReference, runID: "run-1", inProjectAt: root)
    let symbolicPlannerTraceReference = try store.fileReference(
        forProjectRelativePath: symbolicPlannerTracePath,
        artifactID: "planning-symbolic-planner-trace",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(symbolicPlannerTraceReference, runID: "run-1", inProjectAt: root)
    let parameterCandidatesReference = try store.fileReference(
        forProjectRelativePath: parameterCandidatesPath,
        artifactID: "planning-parameter-candidates",
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(parameterCandidatesReference, runID: "run-1", inProjectAt: root)
    let searchTraceReference = try store.fileReference(
        forProjectRelativePath: searchTracePath,
        artifactID: "planning-parameter-candidate-search-trace",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(searchTraceReference, runID: "run-1", inProjectAt: root)
    let selectionTraceReference = try store.fileReference(
        forProjectRelativePath: selectionTracePath,
        artifactID: "planning-parameter-candidate-selection-trace",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(selectionTraceReference, runID: "run-1", inProjectAt: root)
    let planVerificationReference = try store.fileReference(
        forProjectRelativePath: planVerificationPath,
        artifactID: "planning-plan-verification",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(planVerificationReference, runID: "run-1", inProjectAt: root)
    let rejectedPlansReference = try store.fileReference(
        forProjectRelativePath: rejectedPlansPath,
        artifactID: "planning-rejected-plans",
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(rejectedPlansReference, runID: "run-1", inProjectAt: root)
    let planExecutionReference = try store.fileReference(
        forProjectRelativePath: planExecutionPath,
        artifactID: "planning-plan-execution",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(planExecutionReference, runID: "run-1", inProjectAt: root)
    let editedNetlistReference = try store.fileReference(
        forProjectRelativePath: editedNetlistPath,
        artifactID: "candidate-step-1-edited-netlist",
        kind: .netlist,
        format: .spice,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(editedNetlistReference, runID: "run-1", inProjectAt: root)
    let editReportReference = try store.fileReference(
        forProjectRelativePath: editReportPath,
        artifactID: "candidate-step-1-netlist-parameter-edit-report",
        kind: .report,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(editReportReference, runID: "run-1", inProjectAt: root)

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let planningArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-action-domain"
            && $0.artifactID == "planning-action-domain-snapshot"
            && $0.path == planningPath
    })
    #expect(planningArtifact.kind == .other)
    #expect(planningArtifact.format == .json)
    #expect(planningArtifact.sha256 == XcircuiteHasher().sha256(data: planningPayload))
    #expect(planningArtifact.byteCount == Int64(planningPayload.count))
    #expect(planningArtifact.integrity?.status == .verified)
    let problemArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-problem"
            && $0.artifactID == "planning-problem"
            && $0.path == problemPath
    })
    #expect(problemArtifact.kind == .other)
    #expect(problemArtifact.format == .json)
    #expect(problemArtifact.sha256 == XcircuiteHasher().sha256(data: problemPayload))
    #expect(problemArtifact.byteCount == Int64(problemPayload.count))
    #expect(problemArtifact.integrity?.status == .verified)
    let problemTranslationAuditArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-problem-translation-audit"
            && $0.artifactID == "planning-problem-translation-audit"
            && $0.path == problemTranslationAuditPath
    })
    #expect(problemTranslationAuditArtifact.kind == .other)
    #expect(problemTranslationAuditArtifact.format == .json)
    #expect(problemTranslationAuditArtifact.sha256 == XcircuiteHasher().sha256(data: problemTranslationAuditPayload))
    #expect(problemTranslationAuditArtifact.byteCount == Int64(problemTranslationAuditPayload.count))
    #expect(problemTranslationAuditArtifact.integrity?.status == .verified)
    let candidatePlanArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-candidate-plan"
            && $0.artifactID == "planning-candidate-plan"
            && $0.path == candidatePlanPath
    })
    #expect(candidatePlanArtifact.kind == .other)
    #expect(candidatePlanArtifact.format == .json)
    #expect(candidatePlanArtifact.sha256 == XcircuiteHasher().sha256(data: candidatePlanPayload))
    #expect(candidatePlanArtifact.byteCount == Int64(candidatePlanPayload.count))
    #expect(candidatePlanArtifact.integrity?.status == .verified)
    let symbolicPlannerTraceArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-symbolic-planner-trace"
            && $0.artifactID == "planning-symbolic-planner-trace"
            && $0.path == symbolicPlannerTracePath
    })
    #expect(symbolicPlannerTraceArtifact.kind == .other)
    #expect(symbolicPlannerTraceArtifact.format == .json)
    #expect(symbolicPlannerTraceArtifact.sha256 == XcircuiteHasher().sha256(data: symbolicPlannerTracePayload))
    #expect(symbolicPlannerTraceArtifact.byteCount == Int64(symbolicPlannerTracePayload.count))
    #expect(symbolicPlannerTraceArtifact.integrity?.status == .verified)
    let parameterCandidatesArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-parameter-candidates"
            && $0.artifactID == "planning-parameter-candidates"
            && $0.path == parameterCandidatesPath
    })
    #expect(parameterCandidatesArtifact.kind == .other)
    #expect(parameterCandidatesArtifact.format == .text)
    #expect(parameterCandidatesArtifact.sha256 == XcircuiteHasher().sha256(data: parameterCandidatesPayload))
    #expect(parameterCandidatesArtifact.byteCount == Int64(parameterCandidatesPayload.count))
    #expect(parameterCandidatesArtifact.integrity?.status == .verified)
    let searchTraceArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-parameter-candidate-search-trace"
            && $0.artifactID == "planning-parameter-candidate-search-trace"
            && $0.path == searchTracePath
    })
    #expect(searchTraceArtifact.kind == .other)
    #expect(searchTraceArtifact.format == .json)
    #expect(searchTraceArtifact.sha256 == XcircuiteHasher().sha256(data: searchTracePayload))
    #expect(searchTraceArtifact.byteCount == Int64(searchTracePayload.count))
    #expect(searchTraceArtifact.integrity?.status == .verified)
    let selectionTraceArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-parameter-candidate-selection-trace"
            && $0.artifactID == "planning-parameter-candidate-selection-trace"
            && $0.path == selectionTracePath
    })
    #expect(selectionTraceArtifact.kind == .other)
    #expect(selectionTraceArtifact.format == .json)
    #expect(selectionTraceArtifact.sha256 == XcircuiteHasher().sha256(data: selectionTracePayload))
    #expect(selectionTraceArtifact.byteCount == Int64(selectionTracePayload.count))
    #expect(selectionTraceArtifact.integrity?.status == .verified)
    let planVerificationArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-plan-verification"
            && $0.artifactID == "planning-plan-verification"
            && $0.path == planVerificationPath
    })
    #expect(planVerificationArtifact.kind == .other)
    #expect(planVerificationArtifact.format == .json)
    #expect(planVerificationArtifact.sha256 == XcircuiteHasher().sha256(data: planVerificationPayload))
    #expect(planVerificationArtifact.byteCount == Int64(planVerificationPayload.count))
    #expect(planVerificationArtifact.integrity?.status == .verified)
    let planningCorrectnessItem = try #require(bundle.reviewItems.first {
        $0.kind == .planningCorrectness
            && $0.itemID == "planning-correctness-post-execution-signoff"
    })
    #expect(planningCorrectnessItem.status == .needsReview)
    #expect(planningCorrectnessItem.severity == .warning)
    #expect(planningCorrectnessItem.diagnosticCodes == ["post-execution-verification-required"])
    #expect(planningCorrectnessItem.artifactPaths == [planVerificationPath])
    #expect(planningCorrectnessItem.nextActionID == "verify-candidate-plan:post-execution")
    let planningCorrectnessNextAction = try #require(bundle.summary.nextActions.first {
        $0.kind == "verifyPlanningCorrectness"
            && $0.actionID == "verify-candidate-plan:post-execution"
    })
    #expect(planningCorrectnessNextAction.severity == .warning)
    #expect(planningCorrectnessNextAction.diagnosticCodes == ["post-execution-verification-required"])
    let verifyCommand = try #require(planningCorrectnessNextAction.suggestedCommands.first)
    #expect(verifyCommand.commandID == "xcircuite-flow.verify-candidate-plan.post-execution")
    #expect(verifyCommand.readiness == .ready)
    #expect(verifyCommand.executable == "xcircuite-flow")
    #expect(verifyCommand.arguments == [
        "verify-candidate-plan",
        "--project-root",
        root.path(percentEncoded: false),
        "--run-id",
        "run-1",
        "--mode",
        "post-execution",
        "--pretty",
    ])
    let translationAuditNextAction = try #require(bundle.summary.nextActions.first {
        $0.kind == "repairPlanningCorrectness"
            && $0.actionID == "audit-problem-translation"
    })
    #expect(translationAuditNextAction.severity == .warning)
    #expect(translationAuditNextAction.diagnosticCodes == ["problem-translation-audit-required"])
    let auditCommand = try #require(translationAuditNextAction.suggestedCommands.first)
    #expect(auditCommand.commandID == "xcircuite-flow.audit-problem-translation")
    #expect(auditCommand.readiness == .ready)
    #expect(auditCommand.executable == "xcircuite-flow")
    #expect(auditCommand.arguments == [
        "audit-problem-translation",
        "--project-root",
        root.path(percentEncoded: false),
        "--run-id",
        "run-1",
        "--pretty",
    ])
    let rejectedPlansArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-rejected-plans"
            && $0.artifactID == "planning-rejected-plans"
            && $0.path == rejectedPlansPath
    })
    #expect(rejectedPlansArtifact.kind == .other)
    #expect(rejectedPlansArtifact.format == .text)
    #expect(rejectedPlansArtifact.sha256 == XcircuiteHasher().sha256(data: rejectedPlansPayload))
    #expect(rejectedPlansArtifact.byteCount == Int64(rejectedPlansPayload.count))
    #expect(rejectedPlansArtifact.integrity?.status == .verified)
    let planningFeedbackItem = try #require(bundle.reviewItems.first {
        $0.itemID == "planning-rejected-feedback"
    })
    #expect(planningFeedbackItem.kind == .diagnosticReview)
    #expect(planningFeedbackItem.status == .needsReview)
    #expect(planningFeedbackItem.severity == .warning)
    #expect(planningFeedbackItem.diagnosticCodes == ["planning-rejected-feedback-available"])
    #expect(planningFeedbackItem.artifactPaths == [rejectedPlansPath])
    #expect(planningFeedbackItem.nextActionID == "regenerate-candidate-plan-with-feedback")
    let feedbackNextAction = try #require(bundle.summary.nextActions.first {
        $0.kind == "regenerateCandidatePlanWithFeedback"
            && $0.actionID == "regenerate-candidate-plan-with-feedback"
    })
    #expect(feedbackNextAction.severity == .warning)
    #expect(feedbackNextAction.diagnosticCodes == ["planning-rejected-feedback-available"])
    let feedbackCommand = try #require(feedbackNextAction.suggestedCommands.first)
    #expect(feedbackCommand.commandID == "xcircuite-flow.generate-candidate-plan.with-rejected-feedback")
    #expect(feedbackCommand.readiness == .ready)
    #expect(feedbackCommand.executable == "xcircuite-flow")
    #expect(feedbackCommand.arguments == [
        "generate-candidate-plan",
        "--project-root",
        root.path(percentEncoded: false),
        "--run-id",
        "run-1",
        "--rejected-plans-artifact-id",
        "planning-rejected-plans",
        "--pretty",
    ])
    let planExecutionArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-plan-execution"
            && $0.artifactID == "planning-plan-execution"
            && $0.path == planExecutionPath
    })
    #expect(planExecutionArtifact.kind == .other)
    #expect(planExecutionArtifact.format == .json)
    #expect(planExecutionArtifact.sha256 == XcircuiteHasher().sha256(data: planExecutionPayload))
    #expect(planExecutionArtifact.byteCount == Int64(planExecutionPayload.count))
    #expect(planExecutionArtifact.integrity?.status == .verified)
    let editedNetlistArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-edited-netlist"
            && $0.artifactID == "candidate-step-1-edited-netlist"
            && $0.path == editedNetlistPath
    })
    #expect(editedNetlistArtifact.kind == .netlist)
    #expect(editedNetlistArtifact.format == .spice)
    #expect(editedNetlistArtifact.sha256 == XcircuiteHasher().sha256(data: editedNetlistPayload))
    #expect(editedNetlistArtifact.byteCount == Int64(editedNetlistPayload.count))
    #expect(editedNetlistArtifact.integrity?.status == .verified)
    let editReportArtifact = try #require(bundle.artifacts.first {
        $0.role == "planning-netlist-parameter-edit-report"
            && $0.artifactID == "candidate-step-1-netlist-parameter-edit-report"
            && $0.path == editReportPath
    })
    #expect(editReportArtifact.kind == .report)
    #expect(editReportArtifact.format == .json)
    #expect(editReportArtifact.sha256 == XcircuiteHasher().sha256(data: editReportPayload))
    #expect(editReportArtifact.byteCount == Int64(editReportPayload.count))
    #expect(editReportArtifact.integrity?.status == .verified)
}

@Test func reviewBundlerProjectsRetainedCIHistoryForHumanAndAgentReview() async throws {
    let root = try makeTemporaryRoot("agent-review-retained-history")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"
    let dashboardPath = ".xcircuite/runs/\(runID)/retention/signoff-history-dashboard.json"
    let historyPath = ".xcircuite/runs/\(runID)/retention/signoff-history.jsonl"
    let retentionIndexPath = ".xcircuite/runs/\(runID)/retention/signoff-retention-index.json"
    let indexReviewPath = ".xcircuite/runs/\(runID)/retention/retention-index-review.json"
    let budgetPath = ".xcircuite/runs/\(runID)/retention/retained-ci-regression-budget.json"
    let releaseEnvelopePath = ".xcircuite/runs/\(runID)/qualification/release-envelope.json"

    try await createBlockedApprovalRun(root: root, runID: runID)
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"passed","kind":"signoff-qualification-ci-history-dashboard","actionItems":[],"entries":[{"status":"passed"}]}"#.utf8),
        path: dashboardPath,
        artifactID: "signoff-qualification-ci-history-dashboard",
        root: root,
        runID: runID
    )
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"passed"}"#.utf8),
        path: historyPath,
        artifactID: "signoff-qualification-ci-history",
        root: root,
        runID: runID
    )
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"passed","artifactRefs":[]}"#.utf8),
        path: retentionIndexPath,
        artifactID: "signoff-qualification-ci-retention-index",
        root: root,
        runID: runID
    )
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"needsReview","actionItems":[{"code":"retention_index_review_dashboard_ref_byte_count_mismatch","nextAction":"refresh-retention-index"}]}"#.utf8),
        path: indexReviewPath,
        artifactID: "ci-retention-index-review",
        root: root,
        runID: runID
    )
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"failed","failures":[{"code":"retained_ci_regression_budget_evidence_stale"}],"actionItems":[{"code":"retained_ci_regression_budget_refresh_history"}]}"#.utf8),
        path: budgetPath,
        artifactID: "retained-ci-regression-budget",
        root: root,
        runID: runID
    )
    try writeRunArtifact(
        Data(#"{"schemaVersion":1,"status":"blocked","requirements":[{"requirementID":"retained-corpus-history","required":true,"status":"blocked","diagnosticCodes":["release-envelope-corpus-history-stale"]}],"diagnostics":[{"code":"release-envelope-corpus-history-stale","severity":"error"}]}"#.utf8),
        path: releaseEnvelopePath,
        artifactID: "qualification-release-envelope",
        root: root,
        runID: runID
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: runID,
        projectRoot: root
    )

    #expect(bundle.artifacts.contains {
        $0.role == "retained-history-dashboard"
            && $0.artifactID == "signoff-qualification-ci-history-dashboard"
            && $0.integrity?.status == .verified
    })
    #expect(bundle.artifacts.contains { $0.role == "retained-history" && $0.path == historyPath })
    #expect(bundle.artifacts.contains { $0.role == "retention-index" && $0.path == retentionIndexPath })
    #expect(bundle.artifacts.contains { $0.role == "retention-index-review" && $0.path == indexReviewPath })
    #expect(bundle.artifacts.contains { $0.role == "retained-ci-regression-budget" && $0.path == budgetPath })
    #expect(bundle.artifacts.contains { $0.role == "release-envelope" && $0.path == releaseEnvelopePath })
    let item = try #require(bundle.reviewItems.first {
        $0.kind == .retainedHistory && $0.itemID == "review-retained-history"
    })
    #expect(item.status == .needsRepair)
    #expect(item.severity == .error)
    #expect(item.artifactPaths == [
        releaseEnvelopePath,
        budgetPath,
        historyPath,
        dashboardPath,
        retentionIndexPath,
        indexReviewPath,
    ].sorted())
    #expect(item.diagnosticCodes.contains("retention_index_review_dashboard_ref_byte_count_mismatch"))
    #expect(item.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale"))
    #expect(item.diagnosticCodes.contains("release-envelope-corpus-history-stale"))
    #expect(item.diagnosticCodes.contains("release-gate-requirement-blocked:retained-corpus-history"))
    #expect(item.nextActionID == "repair-retained-history-evidence")
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "retained-history"
            && $0.role == "retained-ci-regression-budget"
            && $0.path == budgetPath
            && $0.reviewItemIDs == ["review-retained-history"]
    } == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "release-gate"
            && $0.role == "release-envelope"
            && $0.path == releaseEnvelopePath
            && $0.reviewItemIDs == ["review-retained-history"]
    } == true)
}

@Test func reviewBundlerReportsMissingStageArtifactIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-review-missing-artifact")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"

    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json,
                sha256: String(repeating: "a", count: 64)
            ),
        ]
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let summaryArtifact = try #require(bundle.artifacts.first {
        $0.role == "stage-summary"
            && $0.artifactID == "drc-summary"
            && $0.path == summaryPath
    })
    #expect(summaryArtifact.integrity?.status == .missingArtifact)
    #expect(bundle.reviewItems.contains {
        $0.kind == .artifactIntegrity
            && $0.status == .needsRepair
            && $0.severity == .error
            && $0.stageID == "001-drc"
            && $0.artifactPaths == [summaryPath]
    })
}

@Test func reviewBundlerReportsByteCountMismatchStageArtifactIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-review-byte-mismatch")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)

    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )
    var result = try XcircuitePackageStore().readJSON(
        FlowStageResult.self,
        from: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json")
    )
    result.artifacts[0].byteCount = 1
    try XcircuitePackageStore().writeJSON(
        result,
        to: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json"),
        forProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let summaryArtifact = try #require(bundle.artifacts.first {
        $0.role == "stage-summary"
            && $0.artifactID == "drc-summary"
            && $0.path == summaryPath
    })
    #expect(summaryArtifact.integrity?.status == .byteCountMismatch)
    #expect(summaryArtifact.integrity?.expectedByteCount == 1)
    #expect(summaryArtifact.integrity?.actualByteCount == Int64(summaryPayload.count))
    #expect(bundle.reviewItems.contains {
        $0.kind == .artifactIntegrity
            && $0.status == .needsRepair
            && $0.severity == .error
            && $0.artifactPaths.contains(summaryPath)
    })
}

@Test func reviewBundlerReportsTamperedPlanIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-review-tampered-plan")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    try XcircuitePackageStore().writeJSON(
        FlowRunPlan(
            runID: "run-1",
            intent: "Tampered intent",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        ),
        to: root.appending(path: ".xcircuite/runs/run-1/plan.json"),
        forProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let artifact = try #require(bundle.artifacts.first {
        $0.role == "plan" && $0.path == ".xcircuite/runs/run-1/plan.json"
    })
    #expect([
        FlowRunReviewArtifactIntegrityStatus.byteCountMismatch,
        .sha256Mismatch,
    ].contains(artifact.integrity?.status))
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "integrity"
            && $0.path == ".xcircuite/runs/run-1/plan.json"
            && $0.integrityStatus == artifact.integrity?.status
    } == true)
}

@Test func reviewBundlerReportsTamperedStageResultIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-review-tampered-result")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    try Data(#"{"stageID":"001-drc","status":"blocked","diagnostics":[{"severity":"warning","code":"TAMPERED","message":"tampered"}],"gates":[],"artifacts":[],"attempts":[]}"#.utf8)
        .write(to: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json"), options: .atomic)

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let artifact = try #require(bundle.artifacts.first {
        $0.role == "stage-result" && $0.path == ".xcircuite/runs/run-1/stages/001-drc/result.json"
    })
    #expect([
        FlowRunReviewArtifactIntegrityStatus.byteCountMismatch,
        .sha256Mismatch,
    ].contains(artifact.integrity?.status))
    #expect(bundle.reviewItems.contains {
        $0.kind == .artifactIntegrity
            && $0.status == .needsRepair
            && $0.stageID == "001-drc"
            && $0.artifactPaths.contains(".xcircuite/runs/run-1/stages/001-drc/result.json")
    })
}

@Test func reviewBundlerReportsTamperedApprovalIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-review-tampered-approval")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    var approval = try #require(
        try XcircuitePackageStore().loadApproval(
            runID: "run-1",
            stageID: "001-drc",
            inProjectAt: root
        )
    )
    approval.reviewer = "intruder"
    try XcircuitePackageStore().writeJSON(
        approval,
        to: root.appending(path: ".xcircuite/runs/run-1/approvals/001-drc.json"),
        forProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let artifact = try #require(bundle.artifacts.first {
        $0.role == "approval" && $0.path == ".xcircuite/runs/run-1/approvals/001-drc.json"
    })
    #expect([
        FlowRunReviewArtifactIntegrityStatus.byteCountMismatch,
        .sha256Mismatch,
    ].contains(artifact.integrity?.status))
}

@Test func reviewBundlerVerifiesCancellationAndProgressRecordedAfterRunPersistence() async throws {
    let root = try makeTemporaryRoot("agent-review-post-run-cancel-integrity")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    _ = try DefaultFlowRunCancellationRecorder().requestCancellation(
        projectRoot: root,
        runID: "run-1",
        requestedBy: "reviewer-1",
        reason: "Stop before resume."
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let progress = try #require(bundle.artifacts.first {
        $0.role == "run-progress" && $0.path == ".xcircuite/runs/run-1/progress.jsonl"
    })
    #expect(progress.integrity?.status == .verified)

    let cancellation = try #require(bundle.artifacts.first {
        $0.role == "run-cancellation-request" && $0.path == ".xcircuite/runs/run-1/cancellation.json"
    })
    #expect(cancellation.integrity?.status == .verified)
}

@Test func reviewBundlerReportsUnsafePersistedStageIdentifierAsIntegrityIssue() async throws {
    let root = try makeTemporaryRoot("agent-review-unsafe-stage-id")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let payload = Data(#"{"artifactID":"drc-summary"}"#.utf8)

    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: payload]
    )
    let resultPath = ".xcircuite/runs/run-1/stages/001-drc/result.json"
    var result = try XcircuitePackageStore().readJSON(
        FlowStageResult.self,
        from: root.appending(path: resultPath)
    )
    result.stageID = "../escape"
    try XcircuitePackageStore().writeJSON(
        result,
        to: root.appending(path: resultPath),
        forProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    let summaryArtifact = try #require(bundle.artifacts.first {
        $0.artifactID == "drc-summary" && $0.stageID == "../escape"
    })
    #expect(summaryArtifact.integrity?.status == .invalidIdentifier)
    let stageResultArtifact = try #require(bundle.artifacts.first {
        $0.role == "stage-result" && $0.stageID == "../escape"
    })
    #expect(stageResultArtifact.integrity?.status == .invalidPath)
    let item = try #require(bundle.reviewItems.first {
        $0.kind == .artifactIntegrity && $0.stageID == "../escape"
    })
    #expect(item.severity == .error)
    #expect(item.itemID.hasPrefix("invalid-stage-"))
    #expect(!item.itemID.contains(".."))
    #expect(item.nextActionID?.contains("..") == false)
    #expect(bundle.summary.nextActions.allSatisfy { !$0.actionID.contains("..") && !$0.actionID.contains("/") })
}

@Test func reviewBundlerReportsRecordedApprovalAsResumeItem() async throws {
    let root = try makeTemporaryRoot("agent-review-approved")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let store = XcircuitePackageStore()
    try store.writeApproval(
        XcircuiteApprovalRecord(
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "DRC report reviewed."
        ),
        inProjectAt: root
    )
    try store.appendReviewDecisionAction(
        XcircuiteRunReviewDecisionActionRequest(
            actionID: "waive-drc-width",
            runID: "run-1",
            stageID: "001-drc",
            actor: XcircuiteRunActionActor(kind: .human, identifier: "reviewer-1"),
            decisionKind: .waiver,
            decision: "waived",
            targetID: "drc-width-1",
            targetPath: ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json",
            reason: "Waive known false positive for this retained fixture."
        ),
        inProjectAt: root
    )
    try store.appendReviewDecisionAction(
        XcircuiteRunReviewDecisionActionRequest(
            actionID: "resume-after-approval",
            runID: "run-1",
            stageID: "001-drc",
            actor: XcircuiteRunActionActor(kind: .human, identifier: "reviewer-1"),
            decisionKind: .resume,
            decision: "resume",
            targetID: "001-drc",
            targetPath: ".xcircuite/runs/run-1/approvals/001-drc.json",
            reason: "Resume after approval and waiver review."
        ),
        inProjectAt: root
    )

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    #expect(bundle.approvals.count == 1)
    #expect(bundle.reviewItems.contains {
        $0.kind == .approvalGate
            && $0.status == .readyToResume
            && $0.nextActionID == "001-drc-resume-run"
            && $0.artifactPaths.contains(".xcircuite/runs/run-1/approvals/001-drc.json")
    })
    #expect(bundle.decisionActions?.map(\.decisionKind).contains(.waiver) == true)
    #expect(bundle.decisionActions?.map(\.decisionKind).contains(.resume) == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "approval"
            && $0.stageID == "001-drc"
            && $0.path == ".xcircuite/runs/run-1/approvals/001-drc.json"
    } == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "waiver"
            && $0.decisionActionIDs == ["waive-drc-width"]
    } == true)
    #expect(bundle.coverageRefs?.contains {
        $0.domain == "resume"
            && $0.decisionActionIDs == ["resume-after-approval"]
    } == true)
}

@Test func summarizerReportsArtifactCoverageRepairAction() async throws {
    let root = try makeTemporaryRoot("agent-summary-artifact-coverage")
    defer { removeTemporaryRoot(root) }
    try await createArtifactCoverageFailureRun(root: root, runID: "run-1")

    let summary = try DefaultFlowRunLedgerInspector().inspectRun(
        runID: "run-1",
        projectRoot: root
    )

    #expect(summary.status == .failed)
    #expect(summary.nextActions.contains {
        $0.kind == "repairArtifactCoverage"
            && $0.actionID == "001-drc-repair-drc-artifacts"
            && $0.stageID == "001-drc"
            && $0.severity == .error
            && $0.diagnosticCodes == ["ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED"]
    })
    #expect(summary.nextActions.contains {
        $0.kind == "inspectFailure" && $0.stageID == "001-drc"
    })
}

@Test func reviewBundlerReportsArtifactCoverageRepairItem() async throws {
    let root = try makeTemporaryRoot("agent-review-artifact-coverage")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    try await createArtifactCoverageFailureRun(root: root, runID: "run-1")

    let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
        runID: "run-1",
        projectRoot: root
    )

    #expect(bundle.reviewItems.contains {
        $0.kind == .artifactCoverage
            && $0.status == .needsRepair
            && $0.itemID == "001-drc-repair-drc-artifacts"
            && $0.stageID == "001-drc"
            && $0.severity == .error
            && $0.diagnosticCodes == ["ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED"]
            && $0.artifactPaths.contains(summaryPath)
    })
}

@Test func summarizerReportsToolchainRepairAction() async throws {
    let root = try makeTemporaryRoot("agent-summary-toolchain")
    defer { removeTemporaryRoot(root) }

    let descriptor = drcDescriptor()
    _ = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC with required corpus evidence",
            stages: [
                FlowStageDefinition(
                    stageID: "001-drc",
                    displayName: "DRC",
                    requiredTool: drcRequirement(requiredEvidenceKinds: [.corpus])
                ),
            ]
        ),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed,
                evidence: [ToolEvidence(evidenceID: "smoke-1", kind: .smoke)]
            ),
        ],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

    let summary = try DefaultFlowRunLedgerInspector().inspectRun(
        runID: "run-1",
        projectRoot: root
    )

    #expect(summary.status == .blocked)
    #expect(summary.toolchain?.selectedToolIDs == [])
    #expect(summary.toolchain?.missingSelectionStageIDs == ["001-drc"])
    #expect(summary.toolchain?.rejectedEvaluationCount == 1)
    #expect(summary.nextActions.contains {
        $0.kind == "repairToolchain" && $0.stageID == "001-drc"
    })
    #expect(summary.nextActions.first {
        $0.kind == "repairToolchain"
    }?.diagnosticCodes.contains("MISSING_REQUIRED_EVIDENCE") == true)
}

}
