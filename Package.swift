// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.812.0"
)

let toolQualificationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/ToolQualification.git",
    revision: "01742440a723dd7fc2a426242dc26d4b1c97ac5f"
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
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "ToolQualification", package: "ToolQualification"),
            ]
        ),
        .testTarget(
            name: "DesignFlowKernelTests",
            dependencies: [
                "DesignFlowKernel",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ]
        ),
    ]
)
