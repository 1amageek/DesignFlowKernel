// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "dc792c88e189c822c9f83ea86cf139ee68560dca"
    )

let toolQualificationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("ToolQualification/Package.swift").path
)
    ? .package(path: "../ToolQualification")
    : .package(
        url: "https://github.com/1amageek/ToolQualification.git",
        revision: "c489783a5673bc2dd0b94c438c2f53a65d9a2d8b"
    )

let package = Package(
    name: "DesignFlowKernel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignFlowKernel", targets: ["DesignFlowKernel"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
        toolQualificationDependency,
    ],
    targets: [
        .target(
            name: "DesignFlowKernel",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "ToolQualification", package: "ToolQualification"),
            ]
        ),
        .testTarget(
            name: "DesignFlowKernelTests",
            dependencies: [
                "DesignFlowKernel",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ]
)
