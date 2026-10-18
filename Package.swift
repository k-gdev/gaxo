// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// Homebrew prefix (Apple Silicon). OpenSSL and libplist are linked statically,
/// so Gaxo.app does not need Homebrew at runtime.
let brew = "/opt/homebrew/opt"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let uxplay = "\(root)/Sources/UxPlayLib/uxplay"

let package = Package(
    name: "Gaxo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Gaxo", targets: ["Gaxo"]),
        .executable(name: "gaxo-probe", targets: ["gaxo-probe"]),
    ],
    targets: [
        // UxPlay v1.73.7 lib/ plus Patches/0001, already applied (see Patches/README.md
        // and Sources/UxPlayLib/UPSTREAM.md).
        .target(
            name: "UxPlayLib",
            path: "Sources/UxPlayLib",
            exclude: [
                "UPSTREAM.md",
                "uxplay/CMakeLists.txt",
                "uxplay/llhttp/CMakeLists.txt",
                "uxplay/llhttp/LICENSE-MIT",
                "uxplay/playfair/CMakeLists.txt",
                "uxplay/playfair/LICENSE.md",
            ],
            cSettings: [
                .headerSearchPath("uxplay"),
                .headerSearchPath("uxplay/playfair"),
                .headerSearchPath("uxplay/llhttp"),
                .define("NOHOLD"),
                .define("PLIST_210"),
                .define("PLIST_230"),
                // Upstream code is compiled as-is; its warnings are not ours to fix.
                .unsafeFlags(["-I\(brew)/openssl@3/include", "-I\(brew)/libplist/include", "-w"]),
            ],
            linkerSettings: [
                .unsafeFlags(["\(brew)/openssl@3/lib/libcrypto.a", "\(brew)/libplist/lib/libplist-2.0.a"]),
            ]
        ),
        // Gaxo's C shim: replaces what uxplay.cpp does around the library.
        .target(
            name: "UxPlayEngine",
            dependencies: ["UxPlayLib"],
            path: "Sources/UxPlayEngine",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(uxplay)", "-Wall", "-Wextra", "-Wno-unused-parameter"]),
            ]
        ),
        .target(name: "GaxoCore", dependencies: ["UxPlayEngine"]),
        .executableTarget(name: "gaxo-probe", dependencies: ["GaxoCore"]),
        .executableTarget(name: "Gaxo", dependencies: ["GaxoCore"]),
        .testTarget(name: "GaxoCoreTests", dependencies: ["GaxoCore", "UxPlayEngine"]),
        .testTarget(name: "GaxoAppTests", dependencies: ["Gaxo", "GaxoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
