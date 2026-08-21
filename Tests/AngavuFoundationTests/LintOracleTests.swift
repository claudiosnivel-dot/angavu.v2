import XCTest
import Foundation

/// Oracolo di stile/dead-code (T-003, AC-003-1/2). SwiftLint è la sostituzione
/// deterministica di semgrep/knip (00-INDEX §7). Dove `swiftlint` non è
/// installato (es. runner Linux di questa sessione), l'oracolo è dichiarato NON
/// coperto via XCTSkip — mai un verde finto (L-COL-006). Alla verifica di confine
/// su toolchain Apple gira per davvero, incluso `swiftlint analyze` per il
/// dead-code (unused_declaration).
final class LintOracleTests: XCTestCase {

    private func requireSwiftLint() throws {
        // `/usr/bin/env swiftlint` si avvia comunque: se il binario manca, env esce
        // con 127. Trattiamo nil OPPURE 127 come "non installato" → skip onesto.
        let probe = Shell.run(executable: "swiftlint", args: ["version"], in: PackageRoot.url)
        guard let probe, probe.exitCode != 127 else {
            throw XCTSkip("swiftlint non installato: oracolo di lint non coperto qui (L-COL-006)")
        }
    }

    // AC-003-1: lo scaffold passa `swiftlint lint --strict` con esito 0.
    func testScaffoldPassesStrictLint() throws {
        try requireSwiftLint()
        guard let result = Shell.run(
            executable: "swiftlint",
            args: ["lint", "--strict", "--config", ".swiftlint.yml"],
            in: PackageRoot.url
        ) else {
            throw XCTSkip("swiftlint non eseguibile: oracolo non coperto qui")
        }
        XCTAssertEqual(
            result.exitCode, 0,
            "lo scaffold deve passare lint --strict. Violazioni:\n\(result.stdout)\n\(result.stderr)"
        )
    }

    // AC-003-2: un file "sporco" introdotto ad arte (dichiarazione non usata +
    // force-unwrap sui path critici) fa uscire l'oracolo con esito diverso da 0.
    func testDirtyFixtureFailsStrictLint() throws {
        try requireSwiftLint()
        let fixtureDir = PackageRoot.file("Tests/Fixtures/LintViolation")
        guard let result = Shell.run(
            executable: "swiftlint",
            args: ["lint", "--strict", "--config", ".swiftlint.yml", "--no-cache"],
            in: fixtureDir
        ) else {
            throw XCTSkip("swiftlint non eseguibile: oracolo non coperto qui")
        }
        XCTAssertNotEqual(
            result.exitCode, 0,
            "il file sporco DEVE far fallire lint --strict, invece è passato:\n\(result.stdout)"
        )
    }
}
