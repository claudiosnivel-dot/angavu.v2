import Foundation
import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// FSE-J5 (AC-FSE-J5-1) — Oracolo del sink dei cambi libreria: un delta osservato
// invalida la cache in modo CHIRURGICO (censimento C4/B1), non più col nuke.
//
// Riusa la potatura di FSE-J2: gli id cambiati/rimossi spariscono dalle categorie in
// cache (le altre categorie restano istantanee, nessun ricalcolo del rilevatore) e gli
// aggregati dashboard/report — che dipendono dall'intera libreria — si invalidano. Un
// delta di sole aggiunte invalida gli aggregati ma lascia intatte le categorie in cache.
// La registrazione PhotoKit reale è device-only (AC-FSE-J5-2, non coperta): qui si prova
// il core logico del contratto.

final class StoreInvalidatingLibrarySinkTests: XCTestCase {

    // MARK: - Doppioni

    private func asset(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                     creationDate: Date(timeIntervalSince1970: 1_700_000_000), subtypes: [])
    }

    private func categoryData(keep: [String], removable: [String]) -> CategoryReviewData {
        let ids = keep + removable
        let assets = Dictionary(uniqueKeysWithValues: ids.map { ($0, asset($0)) })
        return CategoryReviewData(review: CategoryReview(keepIds: keep, removableIds: removable),
                                  assets: assets)
    }

    private func populatedStore() -> AnalysisResultsStore {
        let store = AnalysisResultsStore()
        store.set(categoryData(keep: ["k1"], removable: ["r1", "r2"]),
                  for: .category("exactDuplicates"), at: Date())
        store.set(categoryData(keep: ["k9"], removable: ["r9"]),
                  for: .category("similarPhotos"), at: Date())
        store.set(999, for: .dashboard)
        store.set("report", for: .honestReport)
        return store
    }

    /// Store dei derivati in memoria che REGISTRA gli id realmente rimossi, così il test
    /// verifica quali derivati il sink invalida (changed+removed, mai gli added).
    private final class RecordingDerivedStore: DerivedResultStoring {
        private(set) var removedIds: [String] = []
        private(set) var removeAllCount = 0
        func loadAll() throws -> [DerivedKey: DerivedRecordValue] { [:] }
        func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws {}
        func remove(ids: [String]) throws { removedIds.append(contentsOf: ids) }
        func removeAll() throws { removeAllCount += 1 }
    }

    // MARK: - AC-FSE-J5-1 — potatura chirurgica, mai il nuke

    func test_didObserve_removedIds_prunesTouchedCategory_keepsOthers_invalidatesAggregates() {
        let store = populatedStore()

        StoreInvalidatingLibrarySink(store: store)
            .didObserve(IndexDelta(removed: ["r1", "r2"]))

        // Categoria toccata: ANCORA in cache (nessun nuke, nessun rilevatore ri-eseguito),
        // senza gli id eliminati.
        let touched: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertNotNil(touched, "la categoria toccata resta in cache: niente nuke")
        XCTAssertEqual(touched?.review.removableIds, [], "gli id rimossi spariscono dalla categoria")
        XCTAssertEqual(touched?.review.keepIds, ["k1"])
        XCTAssertNil(touched?.assets["r1"])

        // Altra categoria: intatta e ancora in cache (NON è ripartita — il difetto B1).
        let other: CategoryReviewData? = store.value(for: .category("similarPhotos"))
        XCTAssertNotNil(other, "le altre categorie non ripartono: restano in cache")
        XCTAssertEqual(other?.review.removableIds, ["r9"])

        // Aggregati: invalidati (i loro numeri dipendono dall'intera libreria).
        let dash: Int? = store.value(for: .dashboard)
        let report: String? = store.value(for: .honestReport)
        XCTAssertNil(dash, "dashboard invalidata su cambio libreria")
        XCTAssertNil(report, "report invalidato su cambio libreria")
        XCTAssertFalse(store.isEmpty, "invalidazione chirurgica: la cache NON è azzerata (no nuke)")
    }

    func test_didObserve_changedIds_prunesTouchedIds() {
        let store = populatedStore()

        StoreInvalidatingLibrarySink(store: store)
            .didObserve(IndexDelta(changed: [asset("r9")]))

        // L'id cambiato è potato dalla categoria che lo conteneva; l'altra resta piena.
        let similar: CategoryReviewData? = store.value(for: .category("similarPhotos"))
        XCTAssertEqual(similar?.review.removableIds, [], "l'id cambiato è potato")
        let dup: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, ["r1", "r2"], "categoria non toccata: intatta")
    }

    func test_didObserve_onlyAdded_invalidatesAggregates_keepsCategoriesCached() {
        let store = populatedStore()

        StoreInvalidatingLibrarySink(store: store)
            .didObserve(IndexDelta(added: [asset("new-id")]))

        // Sole aggiunte: gli aggregati si invalidano (i conteggi di libreria cambiano)…
        let dash: Int? = store.value(for: .dashboard)
        XCTAssertNil(dash, "una foto aggiunta cambia i conteggi: aggregati invalidati")
        let report: String? = store.value(for: .honestReport)
        XCTAssertNil(report)
        // …ma le categorie già composte restano in cache (un asset nuovo non muta una
        // proposta esistente; si riflette al prossimo ricalcolo della categoria).
        let dup: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, ["r1", "r2"], "categorie in cache intatte su sola aggiunta")
    }

    func test_didObserve_invalidatesDerivedCache_onlyForChangedAndRemoved() throws {
        let derivedStore = RecordingDerivedStore()
        let cache = DerivedResultCache(store: derivedStore)
        let store = AnalysisResultsStore()

        StoreInvalidatingLibrarySink(store: store, derivedCache: cache)
            .didObserve(IndexDelta(added: [asset("added")],
                                   removed: ["removed"],
                                   changed: [asset("changed")]))

        // Solo gli id con un derivato possibile (changed/removed): mai l'added.
        XCTAssertEqual(Set(derivedStore.removedIds), ["removed", "changed"],
                       "i derivati si invalidano per changed+removed, mai per gli added")
    }

    func test_didObserve_emptyDelta_isNoOp() {
        let store = populatedStore()

        StoreInvalidatingLibrarySink(store: store).didObserve(IndexDelta())

        // Delta vuoto: nulla potato, nessun aggregato invalidato (mai un ricalcolo inutile).
        let dash: Int? = store.value(for: .dashboard)
        XCTAssertEqual(dash, 999, "delta vuoto: nessuna invalidazione")
        let dup: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, ["r1", "r2"], "delta vuoto: nulla potato")
    }
}
