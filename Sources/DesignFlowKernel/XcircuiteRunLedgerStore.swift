import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func createRunDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try createRunDirectory(
            for: runID,
            descriptor: XcircuiteRunDescriptor(),
            inProjectAt: projectRoot
        )
    }

    @discardableResult
    public func createRunDirectory(
        for runID: String,
        descriptor: XcircuiteRunDescriptor,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try validateRunIdentity(runID: runID, parentRunID: descriptor.parentRunID)
        try createPackage(at: projectRoot)

        let runURL = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        try ensureRunDirectoryStructure(at: runURL)
        let manifestURL = runURL.appending(path: "manifest.json")
        let lockURL = runURL.appending(path: ".manifest.lock")

        try XcircuiteFileLock.withExclusiveLock(at: lockURL) {
            guard !runLedgerFileExists(manifestURL) else {
                throw XcircuitePackageError.runDirectoryAlreadyExists(runID)
            }
            let manifest = try newRunManifest(runID: runID, descriptor: descriptor)
            try writeJSON(manifest, to: manifestURL, forProjectAt: projectRoot)
        }
        try registerRunAndSynchronizeManifestProjection(
            runID: runID,
            projectRoot: projectRoot
        )
        return runURL
    }

    @discardableResult
    public func ensureRunDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try ensureRunDirectory(
            for: runID,
            descriptor: XcircuiteRunDescriptor(),
            inProjectAt: projectRoot
        )
    }

    @discardableResult
    public func ensureRunDirectory(
        for runID: String,
        descriptor: XcircuiteRunDescriptor,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try validateRunIdentity(runID: runID, parentRunID: descriptor.parentRunID)
        try createPackage(at: projectRoot)

        let runURL = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        try ensureRunDirectoryStructure(at: runURL)
        let manifestURL = runURL.appending(path: "manifest.json")
        let lockURL = runURL.appending(path: ".manifest.lock")

        let createdManifest = try XcircuiteFileLock.withExclusiveLock(at: lockURL) {
            if runLedgerFileExists(manifestURL) {
                let existing = try readJSON(XcircuiteRunManifest.self, from: manifestURL)
                guard existing.runID == runID else {
                    throw XcircuitePackageError.runIdentityMismatch(
                        expected: runID,
                        actual: existing.runID
                    )
                }
                return false
            } else {
                let manifest = try newRunManifest(runID: runID, descriptor: descriptor)
                try writeJSON(manifest, to: manifestURL, forProjectAt: projectRoot)
                return true
            }
        }
        if createdManifest {
            try registerRunAndSynchronizeManifestProjection(
                runID: runID,
                projectRoot: projectRoot
            )
        } else {
            _ = try loadRunManifest(runID: runID, inProjectAt: projectRoot)
        }
        return runURL
    }

    public func loadRunManifest(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        return try XcircuiteFileLock.withSharedLock(at: projectLockURL(projectRoot)) {
            let project = try loadManifest(forProjectAt: projectRoot)
            return try validatedRunManifest(
                runID: runID,
                projectRoot: projectRoot,
                project: project
            )
        }
    }

    public func listRunSnapshots(
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteRunSnapshot] {
        try XcircuiteFileLock.withSharedLock(at: projectLockURL(projectRoot)) {
            let project = try loadManifest(forProjectAt: projectRoot)
            return try project.runs.map { reference in
                let manifest = try validatedRunManifest(
                    runID: reference.runID,
                    projectRoot: projectRoot,
                    project: project
                )
                return XcircuiteRunSnapshot(reference: reference, manifest: manifest)
            }
        }
    }

    @discardableResult
    public func transitionRun(
        runID: String,
        transition: XcircuiteRunTransition,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest {
        try mutateRunManifest(
            runID: runID,
            projectRoot: projectRoot,
            updatedAt: transition.occurredAt
        ) { manifest in
            let previousStatus = manifest.status
            guard previousStatus.canTransition(to: transition.status) else {
                throw XcircuitePackageError.invalidRunTransition(
                    runID: runID,
                    from: previousStatus,
                    to: transition.status
                )
            }

            if previousStatus != transition.status {
                manifest.status = transition.status
                switch transition.status {
                case .created:
                    break
                case .running:
                    if manifest.startedAt == nil {
                        manifest.startedAt = transition.occurredAt
                    }
                    manifest.finishedAt = nil
                case .succeeded, .failed, .cancelled, .blocked, .partial:
                    manifest.finishedAt = transition.occurredAt
                }
            }
            mergeArtifacts(transition.artifacts, into: &manifest)
        }
    }

    @discardableResult
    public func upsertRunArtifacts(
        _ references: [XcircuiteFileReference],
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest {
        for reference in references {
            if let artifactID = reference.artifactID {
                try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
            }
        }
        return try mutateRunManifest(
            runID: runID,
            projectRoot: projectRoot,
            updatedAt: nil
        ) { manifest in
            mergeArtifacts(references, into: &manifest)
        }
    }

    public func updateProjectTopDesignName(
        _ topDesignName: String,
        inProjectAt projectRoot: URL
    ) throws {
        try createPackage(at: projectRoot)
        try updateProjectManifest(forProjectAt: projectRoot) { manifest in
            manifest.identity.topDesignName = topDesignName
        }
    }

    func updateProjectManifest(
        forProjectAt projectRoot: URL,
        _ update: (inout XcircuiteProjectManifest) throws -> Void
    ) throws {
        try ensurePackageDirectory(forProjectAt: projectRoot)
        let lockURL = packageURL(forProjectAt: projectRoot).appending(path: ".project.lock")
        try XcircuiteFileLock.withExclusiveLock(at: lockURL) {
            var manifest = try loadManifest(forProjectAt: projectRoot)
            let original = manifest
            try update(&manifest)
            guard manifest != original else {
                return
            }
            try manifest.validate()
            try saveManifest(manifest, forProjectAt: projectRoot)
        }
    }

    private func newRunManifest(
        runID: String,
        descriptor: XcircuiteRunDescriptor
    ) throws -> XcircuiteRunManifest {
        try XcircuiteRunManifest(
            runID: runID,
            status: .created,
            actor: descriptor.actor,
            intent: descriptor.intent,
            parentRunID: descriptor.parentRunID,
            createdAt: descriptor.createdAt,
            updatedAt: descriptor.createdAt
        )
    }

    private func validateRunIdentity(runID: String, parentRunID: String?) throws {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        if let parentRunID {
            try XcircuiteIdentifierValidator().validate(parentRunID, kind: .runID)
        }
    }

    private func ensureRunDirectoryStructure(at runURL: URL) throws {
        try ensureDirectory(at: runURL)
        try ensureDirectory(at: runURL.appending(path: "stages"))
        try ensureDirectory(at: runURL.appending(path: "reports"))
        try ensureDirectory(at: runURL.appending(path: "approvals"))
        try ensureDirectory(at: runURL.appending(path: "planning"))
        try ensureDirectory(at: runURL.appending(path: "evidence"))
    }

    private func registerRunAndSynchronizeManifestProjection(
        runID: String,
        projectRoot: URL
    ) throws {
        let reference = XcircuiteRunReference(
            runID: runID,
            manifestPath: "\(XcircuitePackage.directoryName)/runs/\(runID)/manifest.json"
        )
        try XcircuiteFileLock.withExclusiveLock(at: projectLockURL(projectRoot)) {
            var project = try loadManifest(forProjectAt: projectRoot)
            if let existing = project.runs.first(where: { $0.runID == runID }) {
                guard existing == reference else {
                    throw XcircuitePackageError.invalidProjectManifest(
                        "run '\(runID)' has a conflicting manifest locator."
                    )
                }
            } else {
                project.runs.append(reference)
                project.runs.sort { $0.runID < $1.runID }
            }
            replaceManifestProjection(
                try makeManifestProjection(runID: runID, projectRoot: projectRoot),
                runID: runID,
                in: &project
            )
            try saveManifest(project, forProjectAt: projectRoot)
        }
    }

    private func runManifestURL(runID: String, projectRoot: URL) throws -> URL {
        try XcircuitePackage(projectRoot: projectRoot)
            .runDirectoryURL(for: runID)
            .appending(path: "manifest.json")
    }

    private func validatedRunManifest(
        runID: String,
        projectRoot: URL,
        project: XcircuiteProjectManifest
    ) throws -> XcircuiteRunManifest {
        guard let runReference = project.runs.first(where: { $0.runID == runID }) else {
            throw XcircuitePackageError.runReferenceNotFound(runID)
        }
        guard let projection = project.files.first(where: {
            $0.artifactID == "run-manifest"
                && $0.producedByRunID == runID
                && $0.path == runReference.manifestPath
        }) else {
            throw XcircuitePackageError.runManifestProjectionMissing(runID)
        }

        let integrity = referenceVerifier.verify(projection, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuitePackageError.runManifestProjectionMismatch(
                runID: runID,
                reason: integrity.message
            )
        }

        let manifestURL = try url(
            forProjectRelativePath: runReference.manifestPath,
            inProjectAt: projectRoot
        )
        let manifest = try readJSON(XcircuiteRunManifest.self, from: manifestURL)
        guard manifest.runID == runID else {
            throw XcircuitePackageError.runIdentityMismatch(
                expected: runID,
                actual: manifest.runID
            )
        }
        return manifest
    }

    private func mutateRunManifest(
        runID: String,
        projectRoot: URL,
        updatedAt: Date?,
        _ mutation: (inout XcircuiteRunManifest) throws -> Void
    ) throws -> XcircuiteRunManifest {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let manifestURL = try runManifestURL(runID: runID, projectRoot: projectRoot)
        let runLockURL = manifestURL.deletingLastPathComponent().appending(path: ".manifest.lock")
        return try XcircuiteFileLock.withExclusiveLock(at: projectLockURL(projectRoot)) {
            var project = try loadManifest(forProjectAt: projectRoot)
            let projectedManifest = try validatedRunManifest(
                runID: runID,
                projectRoot: projectRoot,
                project: project
            )
            let result = try XcircuiteFileLock.withExclusiveLock(at: runLockURL) {
                var manifest = try readJSON(XcircuiteRunManifest.self, from: manifestURL)
                guard manifest == projectedManifest else {
                    throw XcircuitePackageError.runManifestProjectionMismatch(
                        runID: runID,
                        reason: "Manifest changed after its project projection was verified."
                    )
                }
                let original = manifest
                try mutation(&manifest)
                guard manifest != original else {
                    return (manifest: original, changed: false)
                }
                let effectiveUpdatedAt = updatedAt ?? Date()
                manifest.revision = original.revision + 1
                manifest.updatedAt = effectiveUpdatedAt
                try manifest.validate()
                guard effectiveUpdatedAt >= original.updatedAt else {
                    throw XcircuitePackageError.invalidRunManifest(
                        runID: runID,
                        reason: "updatedAt must not precede its previous value."
                    )
                }
                try writeJSON(manifest, to: manifestURL, forProjectAt: projectRoot)
                return (manifest: manifest, changed: true)
            }
            if result.changed {
                replaceManifestProjection(
                    try makeManifestProjection(runID: runID, projectRoot: projectRoot),
                    runID: runID,
                    in: &project
                )
                try saveManifest(project, forProjectAt: projectRoot)
            }
            return result.manifest
        }
    }

    private func mergeArtifacts(
        _ references: [XcircuiteFileReference],
        into manifest: inout XcircuiteRunManifest
    ) {
        for reference in references {
            manifest.artifacts.removeAll {
                $0.path == reference.path
                    || (reference.artifactID != nil && $0.artifactID == reference.artifactID)
            }
            manifest.artifacts.append(reference)
        }
        manifest.artifacts.sort { $0.path < $1.path }
    }

    private func makeManifestProjection(
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let path = "\(XcircuitePackage.directoryName)/runs/\(runID)/manifest.json"
        return try fileReference(
            forProjectRelativePath: path,
            artifactID: "run-manifest",
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }

    private func replaceManifestProjection(
        _ reference: XcircuiteFileReference,
        runID: String,
        in project: inout XcircuiteProjectManifest
    ) {
        project.files.removeAll {
            $0.path == reference.path
                || ($0.artifactID == "run-manifest" && $0.producedByRunID == runID)
        }
        project.files.append(reference)
        project.files.sort { $0.path < $1.path }
    }

    private func projectLockURL(_ projectRoot: URL) -> URL {
        packageURL(forProjectAt: projectRoot).appending(path: ".project.lock")
    }

    private func runLedgerFileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}
