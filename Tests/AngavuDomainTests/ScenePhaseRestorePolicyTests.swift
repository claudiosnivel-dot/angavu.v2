import XCTest
@testable import AngavuDomain

// FSE-J4 — Oracolo della policy del ciclo di vita (`scenePhase`).
//
// Prova le direzioni richieste dagli acceptance_criteria sulla policy PURA (nessun device,
// nessuna SwiftUI — la View resta compilata-non-testata, L-COL-006):
//   • AC-FSE-J4-1: active→background→active con indice NON vuoto → RESTORE (dashboard);
//     con indice VUOTO → FRESH (tasto di scansione).
//   • AC-FSE-J4-2: transizione VERSO background → PERSIST (marker schermata/scansione).
// La policy è pura: due enum di fase + un `Int`.
final class ScenePhaseRestorePolicyTests: XCTestCase {

    // MARK: AC-FSE-J4-2 — verso background → persist

    // Il caso della sequenza «active→background→active»: il primo passo (verso background)
    // è la PERSISTENZA, prima che iOS possa terminare l'app memory-heavy.
    func test_towardBackground_persists() {
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .active, to: .background, indexedCount: 0),
            .persist
        )
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .active, to: .background, indexedCount: 25_000),
            .persist
        )
        // Anche da inactive (active→inactive→background è la sequenza reale di iOS): persist.
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .inactive, to: .background, indexedCount: 10),
            .persist
        )
    }

    // MARK: AC-FSE-J4-1 — background→active → restore|fresh secondo l'indice

    // Secondo passo della sequenza «active→background→active» con indice NON vuoto: RESTORE.
    func test_backgroundToActive_nonEmptyIndex_restores() {
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .background, to: .active, indexedCount: 1),
            .restore
        )
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .background, to: .active, indexedCount: 22_783),
            .restore
        )
    }

    // Secondo passo con indice VUOTO (primo avvio, nessuna scansione ancora): FRESH.
    func test_backgroundToActive_emptyIndex_isFresh() {
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .background, to: .active, indexedCount: 0),
            .fresh
        )
    }

    // MARK: Transizioni transitorie → nessuna azione (contesto preservato)

    // Il ritorno al foreground da `.inactive` (non da background: chiamata/Control Center
    // rientrata) NON è un vero resume: nessun ripristino, il contesto resta com'è.
    func test_inactiveToActive_doesNothing() {
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .inactive, to: .active, indexedCount: 25_000),
            .none
        )
    }

    // active→active (nessun cambio reale) e background→inactive (uscita a metà) non agiscono.
    func test_transientTransitions_doNothing() {
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .active, to: .active, indexedCount: 5),
            .none
        )
        XCTAssertEqual(
            ScenePhaseRestorePolicy.action(from: .background, to: .inactive, indexedCount: 5),
            .none
        )
    }
}
