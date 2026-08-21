import XCTest
import Foundation

/// Oracolo di altitudine (T-002, AC-002-1/2): il grafo dei moduli SwiftPM impone
/// le direzioni consentite; un import proibito dal Domain non compila.
final class AltitudeGraphTests: XCTestCase {

    /// Regole `forbidden` del contratto di altitudine (00-INDEX §1bis), sui moduli.
    private let forbiddenEdges: [(from: String, to: String)] = [
        ("AngavuDomain", "AngavuData"),
        ("AngavuDomain", "AngavuFeatures"),
        ("AngavuData", "AngavuFeatures")
    ]

    // AC-002-1: nel grafo del package, AngavuDomain non raggiunge Data/Features e
    // nessun arco proibito è presente.
    func testModuleGraphHasNoForbiddenEdges() throws {
        // dump-package su una COPIA isolata del solo manifest: non tocca il .build
        // del package sotto test, evitando il lock del workspace SwiftPM esterno.
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("angavu-dump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.copyItem(
            at: PackageRoot.file("Package.swift"),
            to: sandbox.appendingPathComponent("Package.swift")
        )

        guard let result = Shell.swift(
            ["package", "dump-package"],
            in: sandbox,
            isolatedHome: true
        ) else {
            throw XCTSkip("swift non risolvibile: oracolo di grafo non coperto qui (L-COL-006)")
        }
        guard result.exitCode == 0 else {
            return XCTFail("swift package dump-package fallito: \(result.stderr)")
        }
        let deps = try targetDependencies(fromDumpJSON: result.stdout)

        for edge in forbiddenEdges {
            let targets = deps[edge.from] ?? []
            XCTAssertFalse(
                targets.contains(edge.to),
                "arco di altitudine proibito presente: \(edge.from) → \(edge.to)"
            )
        }
        // Direzioni consentite presenti (il grafo non è degenere).
        XCTAssertEqual(deps["AngavuDomain"] ?? [], [], "AngavuDomain deve essere senza dipendenze")
        XCTAssertTrue((deps["AngavuData"] ?? []).contains("AngavuDomain"))
        XCTAssertTrue((deps["AngavuFeatures"] ?? []).contains("AngavuDomain"))
    }

    // AC-002-2: una fixture in cui un target "Domain-like" senza dipendenze importa
    // un target "Data-like" NON compila (l'altitudine è imposta dal grafo).
    func testForbiddenImportBreaksTheBuild() throws {
        let fixture = PackageRoot.file("Tests/Fixtures/AltitudeViolation")
        // Scratch-path fresco: build SEMPRE pulita, così l'esito non dipende da un
        // .build incrementale (dove il search-path condiviso può risolvere per caso
        // un import non dichiarato). L'oracolo deve essere deterministico.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("angavu-altitude-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        guard let result = Shell.swift(
            ["build", "--scratch-path", scratch.path],
            in: fixture,
            isolatedHome: true
        ) else {
            throw XCTSkip("swift non risolvibile: oracolo negativo non coperto qui (L-COL-006)")
        }
        XCTAssertNotEqual(
            result.exitCode, 0,
            "la fixture con import proibito DEVE fallire la build, invece è passata:\n\(result.stdout)"
        )
        let log = (result.stdout + result.stderr).lowercased()
        XCTAssertTrue(
            log.contains("circular dependency")
                || log.contains("no such module")
                || log.contains("datalike"),
            "il fallimento deve riguardare l'import proibito verso il modulo Data-like"
        )
    }

    /// Estrae la mappa target → [dipendenze by-name] dal JSON di dump-package.
    private func targetDependencies(fromDumpJSON json: String) throws -> [String: [String]] {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = root["targets"] as? [[String: Any]] else {
            throw AltitudeError.malformedDump
        }
        var result: [String: [String]] = [:]
        for target in targets {
            guard let name = target["name"] as? String else { continue }
            let deps = (target["dependencies"] as? [[String: Any]]) ?? []
            var names: [String] = []
            for dep in deps {
                // Dipendenza by-name: { "byName": ["AngavuDomain", null] }.
                if let byName = dep["byName"] as? [Any?],
                   let first = byName.first as? String {
                    names.append(first)
                }
                // Dipendenza target: { "target": ["AngavuDomain", null] }.
                if let target = dep["target"] as? [Any?],
                   let first = target.first as? String {
                    names.append(first)
                }
            }
            result[name] = names
        }
        return result
    }

    private enum AltitudeError: Error { case malformedDump }
}
