// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DesignFlowKernel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignFlowKernel", targets: ["DesignFlowKernel"]),
    ],
    dependencies: [
        .package(path: "../CircuiteFoundation"),
        .package(path: "../ToolQualification"),
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
