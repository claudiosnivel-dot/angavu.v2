import XCTest
@testable import AngavuDomain

// FSE-I1 — Oracolo della policy di ripristino al lancio.
//
// Prova le due direzioni della decisione pura (indice persistito vuoto/non vuoto):
//   • AC-FSE-I1-1: indice NON vuoto → RESTORE (dashboard), l'utente non è costretto a
//     ri-scansionare;
//   • AC-FSE-I1-2: indice VUOTO (primo avvio) → FRESH (tasto di scansione).
// La policy è pura (solo un `Int` in ingresso): nessun device, nessun port.
final class LaunchRestorePolicyTests: XCTestCase {

    // AC-FSE-I1-1 — una scansione precedente esiste (indice non vuoto): si ripristina.
    func test_nonEmptyIndex_restores() {
        XCTAssertEqual(LaunchRestorePolicy.decide(indexedCount: 1), .restore)
        XCTAssertEqual(LaunchRestorePolicy.decide(indexedCount: 25_000), .restore)
    }

    // AC-FSE-I1-2 — nessun dato indicizzato (primo avvio): la prima scansione è necessaria.
    func test_emptyIndex_isFresh() {
        XCTAssertEqual(LaunchRestorePolicy.decide(indexedCount: 0), .fresh)
    }

    // Robustezza: un conteggio negativo (non atteso da un indice reale, ma difensivo)
    // non è «una scansione fatta» → resta FRESH, mai un restore su dati inesistenti.
    func test_negativeCount_isFresh() {
        XCTAssertEqual(LaunchRestorePolicy.decide(indexedCount: -1), .fresh)
    }
}
