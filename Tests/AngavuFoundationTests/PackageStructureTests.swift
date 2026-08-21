import XCTest
import AngavuDomain
import AngavuData
import AngavuFeatures

/// Oracolo di struttura del package (T-001, AC-001-1/2).
final class PackageStructureTests: XCTestCase {

    // AC-001-1: i tre moduli sono prodotti e linkabili. Il fatto che questo file
    // compili importandoli, e che i marcatori risolvano, è la prova osservabile.
    func testModulesAreProducedAndLinkable() {
        XCTAssertEqual(AngavuDomain.moduleName, "AngavuDomain")
        XCTAssertEqual(AngavuData.moduleName, "AngavuData")
        XCTAssertEqual(AngavuFeatures.moduleName, "AngavuFeatures")
    }

    // AC-001-2: deployment target iOS 17.0 dichiarato nel manifest SwiftPM…
    func testPackageDeclaresIOS17() throws {
        let manifest = try PackageRoot.contents(of: "Package.swift")
        XCTAssertTrue(
            manifest.contains(".iOS(.v17)"),
            "Package.swift deve dichiarare platforms: [.iOS(.v17)]"
        )
        // Nessun target sotto iOS 17: nessuna dichiarazione .iOS(.vNN) con NN < 17.
        for lower in 9...16 {
            XCTAssertFalse(
                manifest.contains(".iOS(.v\(lower))"),
                "trovato deployment iOS inferiore a 17 (.v\(lower)) nel manifest"
            )
        }
    }

    // …e coerentemente nella fonte canonica dell'app Xcode (Config/Shared.xcconfig).
    func testAppDeploymentTargetIs17() throws {
        let xcconfig = try PackageRoot.contents(of: "Config/Shared.xcconfig")
        let target = deploymentTarget(inXcconfig: xcconfig)
        XCTAssertEqual(target, 17.0, "IPHONEOS_DEPLOYMENT_TARGET deve essere 17.0")
        XCTAssertGreaterThanOrEqual(target ?? 0, 17.0, "nessun target sotto iOS 17.0")

        // La spec XcodeGen deve concordare.
        let projectSpec = try PackageRoot.contents(of: "App/project.yml")
        XCTAssertTrue(
            projectSpec.contains("17.0"),
            "App/project.yml deve dichiarare deploymentTarget iOS 17.0"
        )
    }

    /// Estrae il valore numerico di IPHONEOS_DEPLOYMENT_TARGET da un xcconfig.
    private func deploymentTarget(inXcconfig text: String) -> Double? {
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("IPHONEOS_DEPLOYMENT_TARGET") else { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)
            return Double(value)
        }
        return nil
    }
}
