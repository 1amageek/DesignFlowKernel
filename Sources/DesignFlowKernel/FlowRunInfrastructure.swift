import Foundation
import ToolQualification

public protocol FlowRunInfrastructure:
    FlowArtifactPersisting,
    FlowRunControlArtifactPersisting,
    FlowRunControlLoading,
    FlowRunWorkspacePreparing,
    FlowRunEvidencePersisting,
    FlowRunProgressPersisting,
    ToolQualificationArtifactReading
{}
