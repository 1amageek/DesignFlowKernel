import CircuiteFoundation

public enum FlowArtifactPath {
    public static func relative(_ value: String) throws -> ArtifactRelativePath {
        try ArtifactRelativePath(
            segments: value.split(
                separator: "/",
                omittingEmptySubsequences: false
            ).map(String.init)
        )
    }
}
