import Foundation
import ToolQualification

public protocol FlowRunInfrastructure:
    FlowArtifactPersisting,
    FlowRunControlArtifactPersisting,
    FlowRunControlLoading,
    FlowRunLedgerLoading,
    FlowRunWorkspacePreparing,
    FlowRunEvidencePersisting,
    FlowRunProgressPersisting,
    ToolQualificationArtifactReading
{}
