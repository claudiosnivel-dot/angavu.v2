import Foundation
import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-K2 — Cablaggio del change token nello store (AC-FSE-K2-1/2), con tracker-SPIA.
//
// Il `PHPersistentChangeToken` reale è Livello B/C (device/simulatore con libreria);
// qui, in Livello A, si prova che: (1) il token catturato alla scansione è PERSISTITO
// accanto al record della categoria e sopravvive all'idratazione (relaunch simulato);
// (2) la potatura chirurgica lo conserva, un `set` senza token lo azzera; (3)
// `assessPersistedValidity` NON interroga il tracker a token uguale (tutte `.serve`),
// interroga UNA volta per token distinto e ricompone SOLO la categoria toccata; (4) col
// tracker null-object ogni risultato è `.fullRescan` dichiarato. In coda, la radice di
// composizione `live()` cabla l'adapter PhotoKit reale, non il null-object.

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

final class ChangeTrackerWiringTests: XCTestCase {

    private let stamp = Date(timeIntervalSince1970: 9_000)

    /// Simula la FINE scansione (`HomeView.startScan`): due categorie scritte col token.
    private func seedScan(into store: AnalysisResultsStore, token: Data?) {
        store.set(data(keep: ["D1"], removable: ["D2"]), for: .category("exactDuplicates"),
                  at: stamp, libraryToken: token)
        store.set(data(keep: ["S1"], removable: ["S2"]), for: .category("similarPhotos"),
                  at: stamp, libraryToken: token)
    }

    // Il token della scansione è persistito nel record (write-through) e leggibile.
    func test_set_persistsLibraryTokenWithRecord() {
        let persistence = InMemoryCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        seedScan(into: store, token: tokenA)

        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenA)
        XCTAssertEqual(persistence.records["similarPhotos"]?.libraryToken, tokenA)
        XCTAssertEqual(store.libraryToken(for: .category("exactDuplicates")), tokenA)
    }

    // Relaunch simulato: lo store nuovo idratato ripristina anche il token.
    func test_hydrate_restoresLibraryToken() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let assetsById = Dictionary(uniqueKeysWithValues: ["D1", "D2", "S1", "S2"].map { ($0, photo($0)) })

        let relaunched = AnalysisResultsStore(persistence: persistence)
        try relaunched.hydrate(assetsById: assetsById)

        XCTAssertEqual(relaunched.libraryToken(for: .category("exactDuplicates")), tokenA)
        XCTAssertEqual(relaunched.libraryToken(for: .category("similarPhotos")), tokenA)
    }

    // La potatura chirurgica (J2) ripersiste CONSERVANDO il token (il risultato potato
    // resta valido rispetto allo stesso stato di libreria); un `set` senza token lo azzera.
    func test_pruneKeepsToken_setWithoutTokenClearsIt() {
        let persistence = InMemoryCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        seedScan(into: store, token: tokenA)

        store.pruneDeleted(ids: ["D2"])
        XCTAssertEqual(persistence.records["exactDuplicates"]?.libraryToken, tokenA)
        XCTAssertEqual(persistence.records["exactDuplicates"]?.removableIds, [])

        store.set(data(keep: ["D1"], removable: []), for: .category("exactDuplicates"), at: stamp)
        XCTAssertNil(persistence.records["exactDuplicates"]?.libraryToken, "senza token: azzerato")
        XCTAssertNil(store.libraryToken(for: .category("exactDuplicates")))
    }

    // Invalidare rimuove anche il token (memoria e persistenza seguono insieme).
    func test_invalidate_dropsToken() {
        let persistence = InMemoryCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        seedScan(into: store, token: tokenA)

        store.invalidate(.category("exactDuplicates"))
        XCTAssertNil(store.libraryToken(for: .category("exactDuplicates")))
        store.invalidateAll()
        XCTAssertNil(store.libraryToken(for: .category("similarPhotos")))
    }

    // AC-FSE-K2-1 — token corrente UGUALE a quello salvato: tutte `.serve` e il tracker
    // NON è interrogato per i cambi (a token uguale non c'è nulla da chiedere).
    func test_assess_sameToken_servesAllWithoutQueryingChanges() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let tracker = SpyChangeTracker(token: tokenA)

        let decisions = try AnalysisResultsStore(persistence: persistence).assessPersistedValidity(using: tracker)

        XCTAssertEqual(decisions, ["exactDuplicates": .serve, "similarPhotos": .serve])
        XCTAssertTrue(tracker.changesCalls.isEmpty, "a token uguale nessuna richiesta di delta")
    }

    // AC-FSE-K2-1 — token diverso ma delta vuoto: tutte `.serve`, UNA sola richiesta.
    func test_assess_emptyDelta_servesAllWithOneQuery() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .delta(LibraryChangeDelta())

        let decisions = try AnalysisResultsStore(persistence: persistence).assessPersistedValidity(using: tracker)

        XCTAssertEqual(decisions, ["exactDuplicates": .serve, "similarPhotos": .serve])
        XCTAssertEqual(tracker.changesCalls, [tokenA], "una richiesta per token distinto, non per categoria")
    }

    // AC-FSE-K2-2 — delta che tocca id SOLO dei simili: `similarPhotos` → `.recompose`
    // con gli id toccati; `exactDuplicates` → `.serve`. Mai una ricomposizione globale.
    func test_assess_deltaTouchingOneCategory_recomposesOnlyThat() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .delta(LibraryChangeDelta(inserted: ["NEW"], updated: ["S2"]))

        let decisions = try AnalysisResultsStore(persistence: persistence).assessPersistedValidity(using: tracker)

        XCTAssertEqual(decisions["similarPhotos"], .recompose(touchedIds: ["S2"]))
        XCTAssertEqual(decisions["exactDuplicates"], .serve)
        XCTAssertEqual(tracker.changesCalls, [tokenA])
    }

    // AC-FSE-K2-3 — token scaduto: `.fullRescan` dichiarato per ogni categoria.
    func test_assess_expired_declaresFullRescan() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let tracker = SpyChangeTracker(token: tokenB)
        tracker.outcome = .expired

        let decisions = try AnalysisResultsStore(persistence: persistence).assessPersistedValidity(using: tracker)

        XCTAssertEqual(decisions, ["exactDuplicates": .fullRescan, "similarPhotos": .fullRescan])
    }

    // AC-FSE-K2-3 — tracker null-object (nessun token) o risultati salvati SENZA token:
    // `.fullRescan`, mai servire in silenzio ciò che non è verificabile.
    func test_assess_nullTrackerOrUntrackedRecords_declareFullRescan() throws {
        let persistence = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: persistence), token: tokenA)
        let withNull = try AnalysisResultsStore(persistence: persistence)
            .assessPersistedValidity(using: NoLibraryChangeTracker())
        XCTAssertEqual(withNull, ["exactDuplicates": .fullRescan, "similarPhotos": .fullRescan])

        let untracked = InMemoryCategoryResultStore()
        seedScan(into: AnalysisResultsStore(persistence: untracked), token: nil)
        let tracker = SpyChangeTracker(token: tokenA)
        let decisions = try AnalysisResultsStore(persistence: untracked).assessPersistedValidity(using: tracker)
        XCTAssertEqual(decisions, ["exactDuplicates": .fullRescan, "similarPhotos": .fullRescan])
        XCTAssertTrue(tracker.changesCalls.isEmpty)
    }

    // Il default dell'`AppEnvironment` è il null-object: nessun token finché `live()`
    // non cabla l'adapter reale (mai un tracker finto nei grafi di test).
    func test_environmentDefault_isNullTracker() {
        let env = AppEnvironment(
            authorizer: StubAuthorizer(), enumerator: StubEnumerator(),
            indexReader: StubIndex(), indexWriter: StubIndex(),
            byteResolver: StubByteResolver(), deviceStorage: StubDeviceStorage(),
            videoExporter: NoopVideoExporter(), videoSpecProvider: NoopVideoSpecProvider()
        )
        XCTAssertTrue(env.changeTracker is NoLibraryChangeTracker)
        XCTAssertNil(env.changeTracker.currentToken())
    }
}

// MARK: - Stub minimi per costruire un AppEnvironment di default

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct StubEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct StubIndex: AssetIndexReading, AssetIndexWriting {
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { [] }
    func count() throws -> Int { 0 }
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

// MARK: - Livello A / radice di composizione: il tracker reale è cablato in `live()`

#if canImport(SwiftData) && canImport(Photos)
@available(macOS 14, iOS 17, *)
final class ChangeTrackerCompositionRootTests: XCTestCase {

    // FSE-K2: nel grafo `live()` il tracker è `PHPersistentChangeTracker`, non il
    // null-object — altrimenti al rilancio ogni risultato sarebbe `.fullRescan`.
    func test_liveGraph_wiresRealChangeTrackerNotNullObject() throws {
        let env = try LiveCompositionRoot.make()
        XCTAssertTrue(env.changeTracker is PHPersistentChangeTracker,
                      "changeTracker deve essere l'adapter PhotoKit reale nel grafo live()")
        XCTAssertFalse(env.changeTracker is NoLibraryChangeTracker,
                       "changeTracker NON deve essere il null-object nel grafo live() (FSE-K2)")
    }
}
#endif
