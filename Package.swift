// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DesignFlowKernel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignFlowKernel", targets: ["DesignFlowKernel"]),
        .executable(name: "design-flow", targets: ["DesignFlowCLI"]),
    ],
    dependencies: [
        .package(path: "../XcircuitePackage"),
        .package(path: "../ToolQualification"),
    ],
    targets: [
        .target(
            name: "DesignFlowKernel",
            dependencies: [
                .product(name: "XcircuitePackage", package: "XcircuitePackage"),
                .product(name: "ToolQualification", package: "ToolQualification"),
            ]
        ),
        .target(
            name: "DesignFlowCLISupport",
            dependencies: ["DesignFlowKernel"]
        ),
        .executableTarget(
            name: "DesignFlowCLI",
            dependencies: ["DesignFlowCLISupport"]
        ),
        .testTarget(
            name: "DesignFlowKernelTests",
            dependencies: [
                "DesignFlowKernel",
                "DesignFlowCLISupport",
            ]
        ),
    ]
)
