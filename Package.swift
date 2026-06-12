// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DesignFlowKernel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignFlowKernel", targets: ["DesignFlowKernel"]),
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
        .testTarget(name: "DesignFlowKernelTests", dependencies: ["DesignFlowKernel"]),
    ]
)
