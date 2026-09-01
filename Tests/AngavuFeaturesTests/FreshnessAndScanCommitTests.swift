import Foundation
import XCTest
import AngavuDomain
@testable import AngavuFeatures

// FSE-K3 — Oracolo dello STATO DI FRESCHEZZA nello store, del riallineamento del token
// (`markValid`) e del COMMIT di fine scansione (`ScanResultsCommit`, che sostituisce
// l'`invalidateAll()` cieco di `HomeView.startScan`). Complementare a
// `RestoreHydrationTests` (ripristino in tre passi); diviso in un file a sé per il
// limite di leggibilità (file_length). Persistenza-spia in memoria, nessun device.

private final class InMemoryCategoryResultStore: CategoryResultStoring {
    var records: [String: CategoryResultRecordValue] = [:]
    func loadAll() throws -> [CategoryResultRecordValue] { records.values.sorted { $0.kind < $1.kind } }
    func upsert(_ value: CategoryResultRecordValue) throws { records[value.kind] = value }
    func remove(kind: String) throws { records.removeValue(forKey: kind) }
    func removeAll() throws { records.removeAll() }
}

private let tokenA = Data("token-A".utf8)
private let tokenB = Data("token-B".utf8)

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: Date(timeIntervalSince1970: 1_700_000_000), subtypes: [])
}

private func data(keep: [String], removable: [String]) -> CategoryReviewData {
    let ids = keep + removable
    return CategoryReviewData(
        review: CategoryReview(keepIds: keep, removableIds: removable),
        assets: Dictionary(uniqueKeysWithValues: ids.map { ($0, photo($0)) })
    )
}

final class FreshnessAndScanCommitTests: XCTestCase {

    private let assets = [photo("D1"), photo("D2"), photo("S1"), photo("S2"), photo("U1")]
    private let stamp = Date(timeIntervalSince1970: 9_000)
    private let dupKey = AnalysisResultKey.category(CleanupCategory.exactDuplicates.rawValue)
    private let simKey = AnalysisResultKey.category(CleanupCategory.similarPhotos.rawValue)

    /// La sessione PRECEDENTE (scansione completata): due categorie persistite col token A.
    private func seedPreviousSession() -> InMemoryCategoryResultStore {
        let persistence = InMemoryCategoryResultStore()
        let previous = AnalysisResultsStore(persistence: persistence)
        previous.set(data(keep: ["D1"], removable: ["D2"]), for: dupKey, at: stamp, libraryToken: tokenA)
        previous.set(data(keep: ["S1"], removable: ["S2"]), for: simKey, at: stamp, libraryToken: tokenA)
        return persistence
    }

    // MARK: - Store: freschezza e validazione del token (FSE-K3)

    func test_store_setMarksFresh_markFreshnessIgnoresAbsentKey_invalidateDrops() {
        let store = AnalysisResultsStore()
        store.markFreshness(.updating, for: dupKey)
        XCTAssertNil(store.freshness(for: dupKey), "nessuno stato senza valore")

        store.set(data(keep: ["D1"], removable: ["D2"]), for: dupKey, at: stamp, libraryToken: tokenA)
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        store.markFreshness(.updating, for: dupKey)
        XCTAssertEqual(store.freshness(for: dupKey), .updating)

        store.invalidate(dupKey)
        XCTAssertNil(store.freshness(for: dupKey))
    }

    func test_store_markValid_realignsTokenAndPersists_noopWhenEqualOrAbsent() {
        let persistence = InMemoryCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        store.markValid(at: tokenB, for: dupKey)
        XCTAssertTrue(persistence.records.isEmpty, "no-op su chiave assente")

        store.set(data(keep: ["D1"], removable: ["D2"]), for: dupKey, at: stamp, libraryToken: tokenA)
        store.markValid(at: tokenB, for: dupKey)
        XCTAssertEqual(store.libraryToken(for: dupKey), tokenB)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenB)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.computedAt, stamp, "il timbro resta quello del calcolo")
    }

    // MARK: - Commit di fine scansione (`ScanResultsCommit`, sostituisce l'`invalidateAll` cieco)

    // Un annullamento a metà NON cancella la persistenza precedente valida.
    func test_scanCommit_cancelledOrFailed_leavesPreviousResultsIntact() {
        let persistence = seedPreviousSession()
        let store = AnalysisResultsStore(persistence: persistence)
        _ = try? store.hydrate(assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }))

        let cancelled = ScanResultsCommit.apply(
            state: .cancelled(AnalysisProgress(processed: 1, total: 5)),
            figures: nil, categoryResults: [:], into: store, libraryToken: tokenB
        )
        let failed = ScanResultsCommit.apply(
            state: .failed("boom"), figures: nil, categoryResults: [:], into: store, libraryToken: tokenB
        )

        XCTAssertFalse(cancelled)
        XCTAssertFalse(failed)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenA)
        XCTAssertEqual(persistence.records["similarPhotos"]?.removableIds, ["S2"])
        let stillServed: CategoryReviewData? = store.value(for: dupKey)
        XCTAssertNotNil(stillServed)
    }

    // A scansione completata: le categorie raggiunte sono RIMPIAZZATE (token nuovo,
    // `.fresh`), quelle il cui rilevatore è fallito sono INVALIDATE, gli aggregati
    // ricalcolati (`.dashboard` invalidato senza numeri, `.honestReport` sempre).
    func test_scanCommit_completed_replacesReachedAndInvalidatesMissingCategories() {
        let persistence = seedPreviousSession()
        let store = AnalysisResultsStore(persistence: persistence)
        _ = try? store.hydrate(assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }))
        store.set("old-report", for: .honestReport)
        store.set("old-dashboard", for: .dashboard)

        let committed = ScanResultsCommit.apply(
            state: .completed(indexed: 5, partialCount: false),
            figures: nil,
            categoryResults: [.exactDuplicates: data(keep: ["D1"], removable: ["D2", "U1"])],
            into: store,
            libraryToken: tokenB,
            now: stamp
        )

        XCTAssertTrue(committed)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.removableIds, ["D2", "U1"])
        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenB)
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertNil(persistence.records["similarPhotos"], "rilevatore fallito: invalidata, mai un vecchio valore")
        let sim: CategoryReviewData? = store.value(for: simKey)
        XCTAssertNil(sim)
        let report: String? = store.value(for: .honestReport)
        let dashboard: String? = store.value(for: .dashboard)
        XCTAssertNil(report)
        XCTAssertNil(dashboard, "senza numeri calcolati la dashboard si ricalcola")
    }

    // MARK: - Presentazione pura del badge

    func test_freshnessPresentation_labelsOnlyNonFreshStates() {
        XCTAssertNil(CategoryFreshnessPresentation.label(for: nil))
        XCTAssertNil(CategoryFreshnessPresentation.label(for: .fresh))
        XCTAssertNil(CategoryFreshnessPresentation.symbol(for: .fresh))
        let updating = CategoryFreshnessPresentation.label(for: .updating)
        let rescan = CategoryFreshnessPresentation.label(for: .needsFullRescan)
        XCTAssertNotNil(updating)
        XCTAssertNotNil(rescan)
        XCTAssertNotEqual(updating, rescan)
        XCTAssertNotNil(CategoryFreshnessPresentation.symbol(for: .updating))
        XCTAssertNotNil(CategoryFreshnessPresentation.symbol(for: .needsFullRescan))
    }
}
