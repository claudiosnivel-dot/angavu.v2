import XCTest
@testable import AngavuDomain

// D-1 — Oracolo della formattazione di freschezza. Nessun `Date.now`: l'età è
// passata esplicitamente, così il test è deterministico su Linux/CI. Onestà: oltre
// il minuto l'età è dichiarata, mai un dato spacciato per fresco.

final class RelativeFreshnessTests: XCTestCase {

    func test_underOneMinute_isJustNow() {
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 0), "aggiornato ora")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 59), "aggiornato ora")
    }

    func test_negativeAge_isTreatedAsNow_notAbsurd() {
        // Orologio incoerente (es. cambio di fuso): mai un numero negativo assurdo.
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: -120), "aggiornato ora")
    }

    func test_minutesGranularity_floorsToWholeMinutes() {
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 60), "aggiornato 1 min fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 5 * 60 + 30), "aggiornato 5 min fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 59 * 60), "aggiornato 59 min fa")
    }

    func test_hoursGranularity_singularAndPlural() {
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 3600), "aggiornato 1 ora fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 3 * 3600 + 61), "aggiornato 3 ore fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 23 * 3600), "aggiornato 23 ore fa")
    }

    func test_daysGranularity_singularAndPlural() {
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 86_400), "aggiornato 1 giorno fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 2 * 86_400 + 5), "aggiornato 2 giorni fa")
    }

    func test_boundaries_areExactAndMonotonic() {
        // Al confine esatto si passa alla granularità superiore (mai "60 min fa").
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 3599), "aggiornato 59 min fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 3600), "aggiornato 1 ora fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 86_399), "aggiornato 23 ore fa")
        XCTAssertEqual(RelativeFreshness.label(ageSeconds: 86_400), "aggiornato 1 giorno fa")
    }
}
