import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// D-2 — Oracolo della mappatura avanzamento→presentazione: determinato (frazione
// reale + "X di N") vs indeterminato etichettato. Mai una frazione fabbricata.

final class AnalysisProgressPresentationTests: XCTestCase {

    func test_nilProgress_isIndeterminate_withGivenLabel() {
        let pres = AnalysisProgressPresentation(progress: nil, indeterminateLabel: "Analisi…")
        XCTAssertFalse(pres.isDeterminate)
        XCTAssertNil(pres.fraction, "nessuna frazione inventata quando X/N è ignoto")
        XCTAssertEqual(pres.label, "Analisi…")
    }

    func test_someProgress_isDeterminate_withRealFractionAndLabel() {
        let pres = AnalysisProgressPresentation(
            progress: AnalysisProgress(processed: 3, total: 12),
            indeterminateLabel: "Analisi…"
        )
        XCTAssertTrue(pres.isDeterminate)
        XCTAssertEqual(pres.fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(pres.label, "3 di 12")
    }

    func test_completeProgress_isFullFraction() {
        let pres = AnalysisProgressPresentation(
            progress: AnalysisProgress(processed: 8, total: 8),
            indeterminateLabel: "Analisi…"
        )
        XCTAssertTrue(pres.isDeterminate)
        XCTAssertEqual(pres.fraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(pres.label, "8 di 8")
    }

    func test_zeroTotalProgress_isDeterminateComplete_noDivisionByZero() {
        // Un totale nullo è "completo" per il motore (fraction = 1): nessun NaN.
        let pres = AnalysisProgressPresentation(
            progress: AnalysisProgress(processed: 0, total: 0),
            indeterminateLabel: "Analisi…"
        )
        XCTAssertTrue(pres.isDeterminate)
        XCTAssertEqual(pres.fraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(pres.label, "0 di 0")
    }
}
