import Foundation

/// Localizza la root del package a partire dalla posizione di questo file
/// sorgente (#filePath), senza dipendere dalla working-directory del runner.
enum PackageRoot {
    /// .../Tests/AngavuFoundationTests/Support/PackageRoot.swift → risali 4 livelli.
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // AngavuFoundationTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <root>
    }

    static func file(_ relative: String) -> URL {
        url.appendingPathComponent(relative)
    }

    static func contents(of relative: String) throws -> String {
        try String(contentsOf: file(relative), encoding: .utf8)
    }
}
