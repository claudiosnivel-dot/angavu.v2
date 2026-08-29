import Foundation
import XCTest
import AngavuDomain
@testable import AngavuFeatures

// FSE-J2 (AC-FSE-J2-2) — Oracolo della potatura CHIRURGICA dello store (censimento
// B1/C4). Eliminare id in una categoria pota quella entry SENZA far ripartire le altre
// (che restano in cache, cache hit al tap) e invalida gli aggregati dashboard/report,
// i cui numeri dipendono dall'intera libreria. No-op su insieme vuoto. Rimpiazza il
// `store.invalidateAll()` (nuke) che azzerava TUTTA la cache a ogni eliminazione.

final class SurgicalInvalidationTests: XCTestCase {

    private func asset(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                     creationDate: Date(timeIntervalSince1970: 1_700_000_000), subtypes: [])
    }

    private func data(keep: [String], removable: [String]) -> CategoryReviewData {
        let ids = keep + removable
        let assets = Dictionary(uniqueKeysWithValues: ids.map { ($0, asset($0)) })
        return CategoryReviewData(review: CategoryReview(keepIds: keep, removableIds: removable),
                                  assets: assets)
    }

    private func populatedStore() -> AnalysisResultsStore {
        let store = AnalysisResultsStore()
        store.set(data(keep: ["k1"], removable: ["r1", "r2"]), for: .category("exactDuplicates"), at: Date())
        store.set(data(keep: ["k9"], removable: ["r9"]), for: .category("similarPhotos"), at: Date())
        store.set(999, for: .dashboard)
        store.set("report", for: .honestReport)
        return store
    }

    func test_pruneDeleted_prunesTouchedCategory_keepsOthersCached() {
        let store = populatedStore()

        store.pruneDeleted(ids: ["r1", "r2"])

        // Categoria toccata: ancora in cache (nessun ricalcolo del rilevatore), senza gli id.
        let touched: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertNotNil(touched, "la categoria resta in cache: nessun rilevatore ri-eseguito")
        XCTAssertEqual(touched?.review.keepIds, ["k1"])
        XCTAssertEqual(touched?.review.removableIds, [])
        XCTAssertNil(touched?.assets["r1"], "i metadati degli id eliminati spariscono")
        XCTAssertNil(touched?.assets["r2"])
        XCTAssertNotNil(touched?.assets["k1"], "i keep non toccati restano")

        // Altra categoria: intatta e ancora in cache (NON è ripartita).
        let other: CategoryReviewData? = store.value(for: .category("similarPhotos"))
        XCTAssertNotNil(other, "le altre categorie non ripartono: restano in cache")
        XCTAssertEqual(other?.review.keepIds, ["k9"])
        XCTAssertEqual(other?.review.removableIds, ["r9"])
    }

    func test_pruneDeleted_invalidatesAggregates() {
        let store = populatedStore()

        store.pruneDeleted(ids: ["r1"])

        let dash: Int? = store.value(for: .dashboard)
        let report: String? = store.value(for: .honestReport)
        XCTAssertNil(dash, "i numeri dashboard dipendono dall'intera libreria: invalidati")
        XCTAssertNil(report, "il report dipende dall'intera libreria: invalidato")
    }

    func test_pruneDeleted_prunesIdAcrossEveryCategory_eachStaysCached() {
        // Un id presente in più categorie sparisce da tutte; ciascuna resta in cache.
        let store = AnalysisResultsStore()
        store.set(data(keep: [], removable: ["shared", "a"]), for: .category("catA"), at: Date())
        store.set(data(keep: [], removable: ["shared", "b"]), for: .category("catB"), at: Date())

        store.pruneDeleted(ids: ["shared"])

        let catA: CategoryReviewData? = store.value(for: .category("catA"))
        let catB: CategoryReviewData? = store.value(for: .category("catB"))
        XCTAssertEqual(catA?.review.removableIds, ["a"])
        XCTAssertEqual(catB?.review.removableIds, ["b"])
    }

    func test_pruneDeleted_emptySet_isNoOp_keepsAggregatesAndCategories() {
        let store = populatedStore()

        store.pruneDeleted(ids: [])

        let dash: Int? = store.value(for: .dashboard)
        XCTAssertEqual(dash, 999, "insieme vuoto: nessuna invalidazione")
        let touched: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(touched?.review.removableIds, ["r1", "r2"], "insieme vuoto: nulla potato")
    }
}
