import XCTest
@testable import AngavuDomain

// T-040 — AC-040-1 / AC-040-2. Distanza semantica come valore puro dietro il port
// `FeaturePrinting`; il Domain non importa Vision. Gira senza device.

/// Fake feature-printer: distanze note per coppia (non ordinata) di id. Un id nel
/// set `noFeaturePrint` non ha feature print calcolabile → distanza `nil`.
private final class FakeFeaturePrinter: FeaturePrinting {
    private let distances: [Set<String>: Float]
    private let noFeaturePrint: Set<String>

    init(distances: [Set<String>: Float], noFeaturePrint: Set<String> = []) {
        self.distances = distances
        self.noFeaturePrint = noFeaturePrint
    }

    func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float? {
        if noFeaturePrint.contains(lhs.id) || noFeaturePrint.contains(rhs.id) {
            return nil
        }
        return distances[[lhs.id, rhs.id]]
    }
}

final class FeatureDistanceTests: XCTestCase {

    private func asset(_ id: String) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
    }

    // AC-040-1: il Domain interroga la distanza fra due asset e riceve ESATTAMENTE
    // quella fornita dal provider, senza conoscere Vision.
    func test_domainReceivesProviderDistance() throws {
        let printer = FakeFeaturePrinter(distances: [["a", "b"]: 0.25])

        let distance = try SemanticDistance.between(asset("a"), asset("b"), using: printer)

        XCTAssertEqual(distance, 0.25)
    }

    // Un asset senza feature print calcolabile → distanza nil (il clustering ricadrà
    // sul dHash, mai su un falso "via libera").
    func test_missingFeaturePrintYieldsNilDistance() throws {
        let printer = FakeFeaturePrinter(
            distances: [["a", "b"]: 0.1],
            noFeaturePrint: ["b"]
        )

        let distance = try SemanticDistance.between(asset("a"), asset("b"), using: printer)

        XCTAssertNil(distance)
    }

    // AC-040-2: ispezionando i sorgenti del modulo AngavuDomain, nessuno importa
    // Vision — l'accesso a Vision vive SOLO nel Data layer (altitudine).
    func test_domainSourcesDoNotImportVision() throws {
        let domainSources = Self.domainSourcesDirectory
        let contents = try FileManager.default.contentsOfDirectory(atPath: domainSources.path)
        let swiftFiles = contents.filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(swiftFiles.isEmpty, "sorgenti Domain non trovati in \(domainSources.path)")

        for file in swiftFiles {
            let source = try String(
                contentsOf: domainSources.appendingPathComponent(file),
                encoding: .utf8
            )
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                XCTAssertFalse(
                    trimmed == "import Vision" || trimmed.hasPrefix("import Vision."),
                    "AngavuDomain non deve importare Vision, trovato in \(file): \(trimmed)"
                )
            }
        }
    }

    /// Directory dei sorgenti del Domain, localizzata da #filePath (indipendente
    /// dalla working-directory del runner).
    /// .../Tests/AngavuDomainTests/FeatureDistanceTests.swift → risali 3 livelli.
    private static var domainSourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AngavuDomainTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <root>
            .appendingPathComponent("Sources/AngavuDomain")
    }
}
