import XCTest
@testable import AngavuFeatures

// R-01 — Cifra-hero scalabile. La resa SwiftUI (Font/modificatori) è compilata in
// CI ma non resa nei test (L-COL-006); qui si prova l'ORACOLO puro dello stile:
// text style SEMANTICO (scala col Dynamic Type, non una dimensione fissa),
// `monospacedDigit`, cap del Dynamic Type. Se qualcuno reintroducesse una
// `size:` fissa o togliesse le cifre monospaziate, cambierebbe questi dati.

final class AuroraTypeTests: XCTestCase {

    // Lo stile cifra-hero è semantico (largeTitle), arrotondato, grassetto: nessuna
    // dimensione in punti fissa. È così che scala col Dynamic Type.
    func test_heroNumber_usesSemanticRoundedBoldStyle() {
        let style = AuroraType.heroNumber
        XCTAssertEqual(style.textStyle, .largeTitle)
        XCTAssertTrue(style.rounded)
        XCTAssertTrue(style.bold)
    }

    // Le cifre sono monospaziate: il numero non si allarga/stringe mentre cambia.
    func test_heroNumber_usesMonospacedDigits() {
        XCTAssertTrue(AuroraType.heroNumber.monospacedDigit)
    }

    // C'è un cap del Dynamic Type: la cifra scala ma non si tronca alle AX sizes.
    func test_heroNumber_capsDynamicType() {
        XCTAssertEqual(AuroraType.heroNumber.dynamicTypeCap, .accessibility3)
    }
}
