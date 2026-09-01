import Foundation
import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-K3 — Oracolo del RIPRISTINO al lancio (AC-FSE-K3-1/2), Livello A.
//
// Il bug ricorrente: dopo un cold relaunch lo store era vuoto e ogni categoria
// pesante rigirava il rilevatore. Qui si simula il ripristino su logica PURA
// (persistenza-spia, tracker-spia, rilevatore-spia che conta le invocazioni per
// categoria) attraverso i tre passi del `RestoreHydrationCoordinator`:
// idratazione → piano di validità (delta del change token, policy K2) → ricomposizione
// delle SOLE categorie toccate. Si prova che: (1) con delta vuoto aprire OGNI categoria
// è cache hit — 0 rilevatori, stato `.fresh`; (2) con un delta che tocca solo X, X è
// servita subito `.updating` e poi ricomposta con UNA invocazione del suo rilevatore,
// le altre restano `.fresh` senza rilevatori, token aggiornato; (3) token scaduto →
// `.needsFullRescan` DICHIARATO, nessuna ricomposizione silenziosa; (4) un rilevatore
// fallito invalida la sua sola categoria; (5) il commit di fine scansione
// (`ScanResultsCommit`) non tocca la persistenza precedente su annullamento e la
// rimpiazza solo a scansione completata. Il cold relaunch REALE è Livello B
// (`RelaunchCategoryCacheUITests`, job `ios-uitest`).

// MARK: - Spie

private final class InMemoryCategoryResultStore: CategoryResultStoring {
    var records: [String: CategoryResultRecordValue] = [:]
    func loadAll() throws -> [CategoryResultRecordValue] { records.values.sorted { $0.kind < $1.kind } }
    func upsert(_ value: CategoryResultRecordValue) throws { records[value.kind] = value }
    func remove(kind: String) throws { records.removeValue(forKey: kind) }
    func removeAll() throws { records.removeAll() }
}

private final class SpyChangeTracker: LibraryChangeTracking {
    var token: Data?
    var outcome: LibraryChangeOutcome = .unavailable
    private(set) var changesCalls: [Data] = []
    init(token: Data?) { self.token = token }
    func currentToken() -> Data? { token }
    func changes(since token: Data) -> LibraryChangeOutcome {
        changesCalls.append(token)
        return outcome
    }
}

/// Rilevatore-SPIA per categoria: conta le invocazioni e restituisce il valore
/// preparato (o lancia, se la categoria è dichiarata guasta).
private final class SpyComposer {
    private(set) var calls: [CleanupCategory] = []
    var results: [CleanupCategory: CategoryReviewData] = [:]
    var failing: Set<CleanupCategory> = []

    func compose(_ category: CleanupCategory) throws -> CategoryReviewData {
        calls.append(category)
        if failing.contains(category) { throw DetectorDown() }
        return results[category] ?? data(keep: [], removable: [])
    }
}

private struct DetectorDown: Error {}

private struct FakeAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct FakeEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct StubIndex: AssetIndexReading, AssetIndexWriting {
    let assetsToReturn: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { assetsToReturn }
    func count() throws -> Int { assetsToReturn.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct StubByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .estimated(bytes: fallbackEstimate)
    }
}

private struct StubDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
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

private func makeEnvironment(tracker: any LibraryChangeTracking, assets: [LibraryAsset]) -> AppEnvironment {
    let index = StubIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: StubDeviceStorage(),
        changeTracker: tracker,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

/// Specchio del percorso della View all'apertura di una categoria: cache hit
/// (`CategoryReviewSource.cached`) → servita senza rilevatore; miss → rilevatore-spia.
private func openCategory(
    _ category: CleanupCategory, store: AnalysisResultsStore, composer: SpyComposer
) throws -> CategoryReviewData {
    if let hit = CategoryReviewSource.cached(for: category, in: store) { return hit }
    let composed = try composer.compose(category)
    store.set(composed, for: .category(category.rawValue), at: Date())
    return composed
}

// MARK: - Test

final class RestoreHydrationTests: XCTestCase {

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

    /// Il ripristino simulato: store NUOVO (relaunch) + coordinatore sul grafo dato.
    private func makeRestore(
        persistence: InMemoryCategoryResultStore, tracker: SpyChangeTracker
    ) -> (store: AnalysisResultsStore, coordinator: RestoreHydrationCoordinator) {
        let store = AnalysisResultsStore(persistence: persistence)
        let environment = makeEnvironment(tracker: tracker, assets: assets)
        return (store, RestoreHydrationCoordinator(store: store, environment: environment))
    }

    // AC-FSE-K3-1 — risultati persistiti + token T e delta vuoto (token corrente uguale):
    // dopo il ripristino aprire OGNI categoria è cache hit — 0 rilevatori, stato `.fresh`.
    func test_restore_sameToken_everyCategoryIsFreshCacheHitWithZeroDetectors() throws {
        let persistence = seedPreviousSession()
        let tracker = SpyChangeTracker(token: tokenA)
        let (store, coordinator) = makeRestore(persistence: persistence, tracker: tracker)
        let composer = SpyComposer()
        XCTAssertTrue(store.isEmpty, "prima del ripristino lo store nuovo è vuoto (il bug)")

        let hydrated = try coordinator.hydrate()
        XCTAssertEqual(hydrated, ["exactDuplicates", "similarPhotos"])
        XCTAssertEqual(store.freshness(for: dupKey), .updating, "idratata: servita ma in verifica")
        XCTAssertEqual(store.freshness(for: simKey), .updating)

        let plan = try coordinator.plan()
        XCTAssertEqual(plan.decisions, ["exactDuplicates": .serve, "similarPhotos": .serve])
        XCTAssertTrue(tracker.changesCalls.isEmpty, "a token uguale nessuna richiesta di delta")
        coordinator.apply(plan)
        let recomposed = coordinator.recompose(plan, compose: composer.compose)

        XCTAssertEqual(recomposed, [])
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertEqual(store.freshness(for: simKey), .fresh)
        for category in [CleanupCategory.exactDuplicates, .similarPhotos] {
            let served = try openCategory(category, store: store, composer: composer)
            XCTAssertFalse(served.review.removableIds.isEmpty, "servita dalla cache idratata")
        }
        XCTAssertEqual(composer.calls, [], "0 rilevatori invocati aprendo le categorie")
        let dup: CategoryReviewData? = store.value(for: dupKey)
        XCTAssertEqual(dup?.review, CategoryReview(keepIds: ["D1"], removableIds: ["D2"]))
        XCTAssertNil(store.lastPersistenceError)
    }

    // AC-FSE-K3-1 (variante) — token corrente DIVERSO ma delta vuoto: tutte `.fresh`, 0
    // rilevatori, e il token dei record è ALLINEATO al corrente (il prossimo lancio
    // confronta col token più recente, mai un delta sempre più lungo).
    func test_restore_emptyDelta_allFreshAndTokensRealigned() throws {
        let persistence = seedPreviousSession()
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .delta(LibraryChangeDelta())
        let (store, coordinator) = makeRestore(persistence: persistence, tracker: tracker)
        let composer = SpyComposer()

        try coordinator.hydrate()
        let plan = try coordinator.plan()
        coordinator.apply(plan)
        coordinator.recompose(plan, compose: composer.compose)

        XCTAssertEqual(composer.calls, [])
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertEqual(store.freshness(for: simKey), .fresh)
        XCTAssertEqual(store.libraryToken(for: dupKey), tokenB)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenB, "token allineato nel record")
        XCTAssertEqual(persistence.records["exactDuplicates"]?.removableIds, ["D2"], "il valore è intatto")
        XCTAssertEqual(tracker.changesCalls, [tokenA], "una sola richiesta di delta per token distinto")
    }

    // AC-FSE-K3-2 — delta che tocca id della SOLA categoria X (simili): X è servita subito
    // come `.updating`, poi ricomposta con UNA invocazione del suo rilevatore; le altre
    // restano `.fresh` senza rilevatori; token aggiornato al corrente.
    func test_restore_deltaTouchingOneCategory_servesUpdatingThenRecomposesOnlyThat() throws {
        let persistence = seedPreviousSession()
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .delta(LibraryChangeDelta(inserted: ["NEW"], updated: ["S2"]))
        let (store, coordinator) = makeRestore(persistence: persistence, tracker: tracker)
        let composer = SpyComposer()
        composer.results[.similarPhotos] = data(keep: ["S1"], removable: ["S2", "NEW"])

        try coordinator.hydrate()
        let plan = try coordinator.plan()
        XCTAssertEqual(plan.decisions["similarPhotos"], .recompose(touchedIds: ["S2"]))
        XCTAssertEqual(plan.decisions["exactDuplicates"], .serve)
        XCTAssertEqual(plan.kindsToRecompose, ["similarPhotos"])
        XCTAssertFalse(plan.needsFullRescan)
        coordinator.apply(plan)

        // Servita SUBITO (valore idratato), dichiarata `.updating`; l'altra è già `.fresh`.
        XCTAssertEqual(store.freshness(for: simKey), .updating)
        let servedWhileUpdating: CategoryReviewData? = store.value(for: simKey)
        XCTAssertEqual(servedWhileUpdating?.review, CategoryReview(keepIds: ["S1"], removableIds: ["S2"]))
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertEqual(composer.calls, [], "nessun rilevatore prima della ricomposizione")

        let recomposed = coordinator.recompose(plan, compose: composer.compose)

        XCTAssertEqual(recomposed, ["similarPhotos"])
        XCTAssertEqual(composer.calls, [.similarPhotos], "UNA sola invocazione, solo per la categoria toccata")
        XCTAssertEqual(store.freshness(for: simKey), .fresh)
        let fresh: CategoryReviewData? = store.value(for: simKey)
        XCTAssertEqual(fresh?.review, CategoryReview(keepIds: ["S1"], removableIds: ["S2", "NEW"]))
        XCTAssertEqual(store.libraryToken(for: simKey), tokenB, "token aggiornato")
        XCTAssertEqual(persistence.records["similarPhotos"]?.libraryToken, tokenB)
        XCTAssertEqual(persistence.records["similarPhotos"]?.removableIds, ["S2", "NEW"], "ripersistita")
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.removableIds, ["D2"], "l'altra è intatta")
        _ = try openCategory(.exactDuplicates, store: store, composer: composer)
        XCTAssertEqual(composer.calls, [.similarPhotos], "aprire l'altra categoria non invoca rilevatori")
    }

    // Token scaduto/assente: `.needsFullRescan` DICHIARATO, valore ancora servito (con
    // badge), NESSUNA ricomposizione né scansione silenziosa.
    func test_restore_expiredToken_declaresFullRescanWithoutSilentRecompose() throws {
        let persistence = seedPreviousSession()
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .expired
        let (store, coordinator) = makeRestore(persistence: persistence, tracker: tracker)
        let composer = SpyComposer()

        try coordinator.hydrate()
        let plan = try coordinator.plan()
        XCTAssertTrue(plan.needsFullRescan)
        XCTAssertEqual(plan.kindsToRecompose, [])
        coordinator.apply(plan)
        coordinator.recompose(plan, compose: composer.compose)

        XCTAssertEqual(composer.calls, [])
        XCTAssertEqual(store.freshness(for: dupKey), .needsFullRescan)
        XCTAssertEqual(store.freshness(for: simKey), .needsFullRescan)
        let stillServed: CategoryReviewData? = store.value(for: dupKey)
        XCTAssertNotNil(stillServed, "servita con badge onesto, mai uno store svuotato")
        XCTAssertEqual(store.libraryToken(for: dupKey), tokenA, "il token NON è allineato: non verificato")
    }

    // Un rilevatore che FALLISCE nella ricomposizione invalida la SUA sola categoria
    // (memoria e persistenza: si ricompone al tap), mai un `.updating` eterno; l'altra
    // categoria resta intatta e `.fresh`.
    func test_recompose_failure_invalidatesOnlyThatCategory() throws {
        let persistence = seedPreviousSession()
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .delta(LibraryChangeDelta(deleted: ["S2"]))
        let (store, coordinator) = makeRestore(persistence: persistence, tracker: tracker)
        let composer = SpyComposer()
        composer.failing = [.similarPhotos]

        try coordinator.hydrate()
        let plan = try coordinator.plan()
        coordinator.apply(plan)
        let recomposed = coordinator.recompose(plan, compose: composer.compose)

        XCTAssertEqual(recomposed, [])
        XCTAssertEqual(composer.calls, [.similarPhotos])
        XCTAssertNil(store.freshness(for: simKey))
        let gone: CategoryReviewData? = store.value(for: simKey)
        XCTAssertNil(gone, "la categoria guasta è invalidata: si ricompone al tap")
        XCTAssertNil(persistence.records["similarPhotos"])
        XCTAssertEqual(store.freshness(for: dupKey), .fresh)
        XCTAssertNotNil(persistence.records["exactDuplicates"])
    }

    // Persistenza illeggibile: nulla è idratato (mai un risultato inventato) e l'errore
    // è propagato al chiamante, che degrada al comportamento pre-K3 (rilevatore al tap).
    func test_hydrate_unreadablePersistence_throwsAndHydratesNothing() {
        let broken = BrokenCategoryResultStore()
        let store = AnalysisResultsStore(persistence: broken)
        let coordinator = RestoreHydrationCoordinator(
            store: store, environment: makeEnvironment(tracker: SpyChangeTracker(token: tokenA), assets: assets)
        )

        XCTAssertThrowsError(try coordinator.hydrate())
        XCTAssertTrue(store.isEmpty)
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

private struct BrokenCategoryResultStore: CategoryResultStoring {
    struct Unreadable: Error {}
    func loadAll() throws -> [CategoryResultRecordValue] { throw Unreadable() }
    func upsert(_ value: CategoryResultRecordValue) throws {}
    func remove(kind: String) throws {}
    func removeAll() throws {}
}
