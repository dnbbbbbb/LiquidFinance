// swift-tools-version:5.9
import PackageDescription

// LiquidFinanceCore: Data + Domain + Backup layers, UI-free so it is unit-testable
// with `swift test` on macOS. The SwiftUI app (App/) links this package.
let package = Package(
    name: "LiquidFinanceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LiquidFinanceCore", targets: ["LiquidFinanceCore"])],
    targets: [
        .target(name: "LiquidFinanceCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "LiquidFinanceCoreTests", dependencies: ["LiquidFinanceCore"]),
    ]
)
