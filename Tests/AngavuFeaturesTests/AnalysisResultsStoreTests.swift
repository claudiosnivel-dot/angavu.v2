import Foundation
import XCTest
@testable import AngavuFeatures

// P0-1 — Store dei risultati d'analisi: oracolo della logica pura (set/get/
// invalidate). La sopravvivenza al background è View-level (non coperta, L-COL-006);
// qui si prova che il cache memorizza, restituisce col tipo giusto, e invalida.

final class AnalysisResultsStoreTests: XCTestCase {

    func test_emptyByDefault_missReturnsNil() {
        let store = AnalysisResultsStore()
        XCTAssertTrue(store.isEmpty)
        let miss: Int? = store.value(for: .dashboard)
        XCTAssertNil(miss)
    }

    func test_setThenGet_returnsStoredValueOfExpectedType() {
        let store = AnalysisResultsStore()
        store.set(42, for: .dashboard)
        let hit: Int? = store.value(for: .dashboard)
        XCTAssertEqual(hit, 42)
        XCTAssertFalse(store.isEmpty)
    }

    func test_get_wrongType_returnsNilNotCrash() {
        let store = AnalysisResultsStore()
        store.set("stringa", for: .honestReport)
        // Chiedo il tipo sbagliato: miss pulito, non un crash.
        let wrong: Int? = store.value(for: .honestReport)
        XCTAssertNil(wrong)
        // Il valore vero è ancora recuperabile col tipo giusto.
        let right: String? = store.value(for: .honestReport)
        XCTAssertEqual(right, "stringa")
    }

    func test_setOverwrites_previousValue() {
        let store = AnalysisResultsStore()
        store.set(1, for: .dashboard)
        store.set(2, for: .dashboard)
        let hit: Int? = store.value(for: .dashboard)
        XCTAssertEqual(hit, 2)
    }

    func test_invalidateSingleKey_forcesMissForThatKeyOnly() {
        let store = AnalysisResultsStore()
        store.set(10, for: .dashboard)
        store.set(20, for: .honestReport)

        store.invalidate(.dashboard)

        let gone: Int? = store.value(for: .dashboard)
        let kept: Int? = store.value(for: .honestReport)
        XCTAssertNil(gone, "la chiave invalidata ricalcolerà")
        XCTAssertEqual(kept, 20, "le altre chiavi restano valide")
    }

    func test_categoryKeys_areIndependentPerIdentifier() {
        let store = AnalysisResultsStore()
        store.set(1, for: .category("screenshots"))
        store.set(2, for: .category("duplicates"))

        let shot: Int? = store.value(for: .category("screenshots"))
        let dup: Int? = store.value(for: .category("duplicates"))
        XCTAssertEqual(shot, 1)
        XCTAssertEqual(dup, 2)

        store.invalidate(.category("screenshots"))
        let goneA: Int? = store.value(for: .category("screenshots"))
        let keptB: Int? = store.value(for: .category("duplicates"))
        XCTAssertNil(goneA)
        XCTAssertEqual(keptB, 2)
    }

    func test_invalidateAll_clearsEverything() {
        let store = AnalysisResultsStore()
        store.set(1, for: .dashboard)
        store.set(2, for: .honestReport)
        store.set(3, for: .category("screenshots"))

        store.invalidateAll()

        XCTAssertTrue(store.isEmpty)
        let dash: Int? = store.value(for: .dashboard)
        XCTAssertNil(dash)
    }

    // MARK: - D-1 Timestamp di freschezza

    func test_setWithoutTimestamp_recordsNoTimestamp() {
        let store = AnalysisResultsStore()
        store.set(1, for: .dashboard)
        XCTAssertNil(store.timestamp(for: .dashboard),
                     "il badge di freschezza non è tracciato per chi non lo fornisce")
    }

    func test_setWithTimestamp_isReadableBack() {
        let store = AnalysisResultsStore()
        let stamp = Date(timeIntervalSince1970: 1_000)
        store.set(7, for: .category("screenshots"), at: stamp)
        XCTAssertEqual(store.timestamp(for: .category("screenshots")), stamp)
    }

    func test_setWithoutTimestamp_preservesPreviousTimestamp() {
        // Un ricalcolo che non timbra non deve cancellare la freschezza già nota.
        let store = AnalysisResultsStore()
        let stamp = Date(timeIntervalSince1970: 2_000)
        store.set(1, for: .category("dup"), at: stamp)
        store.set(2, for: .category("dup")) // ri-set senza timestamp
        XCTAssertEqual(store.timestamp(for: .category("dup")), stamp)
        let value: Int? = store.value(for: .category("dup"))
        XCTAssertEqual(value, 2)
    }

    func test_invalidate_clearsTimestampToo() {
        let store = AnalysisResultsStore()
        store.set(1, for: .category("x"), at: Date(timeIntervalSince1970: 3_000))
        store.invalidate(.category("x"))
        XCTAssertNil(store.timestamp(for: .category("x")))
    }

    func test_invalidateAll_clearsAllTimestamps() {
        let store = AnalysisResultsStore()
        store.set(1, for: .dashboard, at: Date(timeIntervalSince1970: 4_000))
        store.set(2, for: .category("y"), at: Date(timeIntervalSince1970: 5_000))
        store.invalidateAll()
        XCTAssertNil(store.timestamp(for: .dashboard))
        XCTAssertNil(store.timestamp(for: .category("y")))
    }
}
