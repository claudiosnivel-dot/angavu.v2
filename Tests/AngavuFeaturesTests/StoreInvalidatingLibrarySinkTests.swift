import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// D-1 — Oracolo del sink dei cambi libreria: un delta osservato invalida la cache,
// così nessun numero stantìo sopravvive a un cambio libreria. La registrazione
// PhotoKit reale è device-only (non coperta); qui si prova il core del contratto.

final class StoreInvalidatingLibrarySinkTests: XCTestCase {

    func test_didObserve_invalidatesAllCachedResults() {
        let store = AnalysisResultsStore()
        store.set(1, for: .dashboard)
        store.set(2, for: .honestReport)
        store.set(3, for: .category("screenshots"))
        XCTAssertFalse(store.isEmpty)

        let sink = StoreInvalidatingLibrarySink(store: store)
        sink.didObserve(IndexDelta(removed: ["a-removed-id"]))

        XCTAssertTrue(store.isEmpty, "un cambio libreria rende stantìi tutti i numeri")
        let dash: Int? = store.value(for: .dashboard)
        XCTAssertNil(dash)
    }

    func test_didObserve_withAddedAssets_alsoInvalidates() {
        let store = AnalysisResultsStore()
        store.set(42, for: .category("duplicates"))

        let asset = LibraryAsset(
            id: "new-id",
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        StoreInvalidatingLibrarySink(store: store).didObserve(IndexDelta(added: [asset]))

        let cached: Int? = store.value(for: .category("duplicates"))
        XCTAssertNil(cached)
    }
}
