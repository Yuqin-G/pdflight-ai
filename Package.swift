// swift-tools-version: 6.2

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let muPDFRoot = "\(packageRoot)/Vendor/mupdf"
let muPDFBuild = "\(muPDFRoot)/build/release-tofu"

let package = Package(
    name: "PDFlight",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFlightCore", targets: ["PDFlightCore"]),
        .library(name: "PDFlightAI", targets: ["PDFlightAI"]),
        .library(name: "PDFlightMuPDF", targets: ["PDFlightMuPDF"]),
        .executable(name: "PDFlight", targets: ["PDFlightApp"]),
        .executable(name: "PDFlightCoreChecks", targets: ["PDFlightCoreChecks"]),
        .executable(name: "PDFlightAIChecks", targets: ["PDFlightAIChecks"]),
        .executable(name: "PDFlightMuPDFChecks", targets: ["PDFlightMuPDFChecks"])
    ],
    dependencies: [
        .package(url: "https://github.com/kostub/iosMath.git", from: "2.1.0")
    ],
    targets: [
        .target(name: "PDFlightCore"),
        .target(
            name: "PDFlightAI",
            dependencies: ["PDFlightCore"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "CMuPDF",
            path: "Sources/CMuPDF",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags([
                    "-I\(muPDFRoot)/include",
                    "-DFZ_ENABLE_BROTLI=0",
                    "-DFZ_ENABLE_JS=0",
                    "-DFZ_ENABLE_HTML_ENGINE=0",
                    "-DFZ_ENABLE_HTML=0",
                    "-DFZ_ENABLE_EPUB=0",
                    "-DFZ_ENABLE_FB2=0",
                    "-DFZ_ENABLE_MD=0",
                    "-DFZ_ENABLE_MOBI=0",
                    "-DFZ_ENABLE_OFFICE=0",
                    "-DFZ_ENABLE_TXT=0",
                    "-DFZ_ENABLE_XPS=0",
                    "-DFZ_ENABLE_SVG=0",
                    "-DFZ_ENABLE_DOCX_OUTPUT=0"
                ])
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(muPDFBuild)", "-lmupdf", "-lmupdf-third", "-lc++"])
            ]
        ),
        .executableTarget(
            name: "PDFlightCoreChecks",
            dependencies: ["PDFlightCore"]
        ),
        .executableTarget(
            name: "PDFlightAIChecks",
            dependencies: ["PDFlightCore", "PDFlightAI"]
        ),
        .target(
            name: "PDFlightMuPDF",
            dependencies: ["PDFlightCore", "CMuPDF"]
        ),
        .executableTarget(
            name: "PDFlightMuPDFChecks",
            dependencies: ["PDFlightCore", "PDFlightMuPDF"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("PDFKit")
            ]
        ),
        .executableTarget(
            name: "PDFlightApp",
            dependencies: [
                "PDFlightCore",
                "PDFlightAI",
                "PDFlightMuPDF",
                .product(name: "iosMath", package: "iosMath")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
