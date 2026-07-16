import Foundation
import ToolQualification

public protocol FlowRunInfrastructure:
    FlowArtifactPersisting,
    FlowRunControlLoading,
    FlowRunWorkspacePreparing,
    FlowRunEvidencePersisting,
    FlowRunProgressPersisting,
    ToolQualificationArtifactReading
{}
