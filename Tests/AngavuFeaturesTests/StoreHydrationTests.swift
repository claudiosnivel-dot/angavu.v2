import Foundation
import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-K1 — Oracolo dello store IDRATABILE + write-through (AC-FSE-K1-1/2/3).
//
// Il bug ricorrente: i risultati per categoria vivevano solo in memoria e il
// ripristino al lancio non scansiona → dopo un cold relaunch lo store era vuoto e
// ogni categoria pesante rigirava il rilevatore. Qui si prova, su logica PURA
// (persistenza-spia in memoria, nessun device): (1) uno store NUOVO idratato dalla
// persistenza serve keep/removable IDENTICI; (2) aprire una categoria su uno store
// idratato NON invoca i rilevatori (contatore-spia fermo), mentre su uno store vuoto
// li invoca — il contrasto che rende il «0» significativo; (3) `set` e potatura
// chirurgica ripersistono (write-through); una persistenza che fallisce è RIPORTATA,
// mai inghiottita. In coda, al confine Apple, lo stesso giro passa dallo store
// SwiftData reale (nuovo store sullo stesso container = relaunch simulato).

// MARK: - Persistenza-spia (pura)

private final class SpyCategoryResultStore: CategoryResultStoring {
    var records: [String: CategoryResultRecordValue] = [:]
    var upserts: [CategoryResultRecordValue] = []
    var removedKinds: [String] = []
    var removeAllCount = 0
    /// Se impostato, ogni scrittura lancia (persistenza guasta).
    var failure: Error?

    func loadAll() throws -> [CategoryResultRecordValue] {
        records.values.sorted { $0.kind < $1.kind }
    }

    func upsert(_ value: CategoryResultRecordValue) throws {
        if let failure { throw failure }
        upserts.append(value)
        records[value.kind] = value
    }

    func remove(kind: String) throws {
        if let failure { throw failure }
        removedKinds.append(kind)
        records.removeValue(forKey: kind)
    }

    func removeAll() throws {
        if let failure { throw failure }
        removeAllCount += 1
        records.removeAll()
    }
}

private struct PersistenceDown: Error {}

// MARK: - Fake dei port + rilevatore-spia

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

private struct MapByteResolver: AssetByteSizeResolving {
    let bytesById: [String: Int64]
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        if let bytes = bytesById[localIdentifier] { return .exact(bytes: bytes) }
        return .estimated(bytes: fallbackEstimate)
    }
}

private struct FakeDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

/// Rilevatore-SPIA: conta le invocazioni del hashing (la parte costosa dei duplicati
/// esatti). «0» dopo un'idratazione = la cache è colpita, nessun rilevatore.
private final class SpyHasher: AssetContentHashing {
    private(set) var calls = 0
    let digestsById: [String: String]
    init(digestsById: [String: String]) { self.digestsById = digestsById }
    func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        calls += 1
        return digestsById[asset.id].map(AssetDigest.init)
    }
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: Date(timeIntervalSince1970: 1_700_000_000), subtypes: [])
}

/// Ambiente con due duplicati esatti (D1/D2, stessi byte e stesso digest) e un unico.
private func makeEnvironment(hasher: SpyHasher, assets: [LibraryAsset]) -> AppEnvironment {
    let index = StubIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(bytesById: ["D1": 500, "D2": 500, "U1": 999]),
        deviceStorage: FakeDeviceStorage(),
        contentHasher: hasher,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

private func data(keep: [String], removable: [String]) -> CategoryReviewData {
    let ids = keep + removable
    return CategoryReviewData(
        review: CategoryReview(keepIds: keep, removableIds: removable),
        assets: Dictionary(uniqueKeysWithValues: ids.map { ($0, photo($0)) })
    )
}

/// Specchio del percorso della View (`CategoryReviewView.loadIfNeeded`): cache hit
/// (`CategoryReviewSource.cached`, la stessa decisione della View) → servita, nessun
/// rilevatore; miss → composizione dai port + cache col timestamp (write-through).
private func openCategory(
    _ category: CleanupCategory, store: AnalysisResultsStore, environment: AppEnvironment
) throws -> CategoryReviewData {
    if let hit = CategoryReviewSource.cached(for: category, in: store) { return hit }
    let data = try CategoryReviewSource.reviewData(for: category, from: environment)
    store.set(data, for: .category(category.rawValue), at: Date())
    return data
}

// MARK: - Test

final class StoreHydrationTests: XCTestCase {

    private let assets = [photo("D1"), photo("D2"), photo("U1"), photo("S1"), photo("S2")]
    private var assetsById: [String: LibraryAsset] {
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    }

    // AC-FSE-K1-1 — risultati salvati (write-through) → store NUOVO sulla stessa
    // persistenza (relaunch simulato) idratato → keep/removable IDENTICI, per ogni
    // categoria, col timestamp di freschezza ripristinato.
    func test_hydrate_newStoreServesIdenticalResults() throws {
        let persistence = SpyCategoryResultStore()
        let stamp = Date(timeIntervalSince1970: 5_000)
        let first = AnalysisResultsStore(persistence: persistence)
        first.set(data(keep: ["D1"], removable: ["D2"]), for: .category("exactDuplicates"), at: stamp)
        first.set(data(keep: ["S1"], removable: ["S2"]), for: .category("similarPhotos"), at: stamp)

        let relaunched = AnalysisResultsStore(persistence: persistence)
        XCTAssertTrue(relaunched.isEmpty, "prima dell'idratazione lo store nuovo è vuoto (il bug)")

        let hydrated = try relaunched.hydrate(assetsById: assetsById)

        XCTAssertEqual(hydrated, ["exactDuplicates", "similarPhotos"])
        let dup: CategoryReviewData? = relaunched.value(for: .category("exactDuplicates"))
        let sim: CategoryReviewData? = relaunched.value(for: .category("similarPhotos"))
        XCTAssertEqual(dup?.review, CategoryReview(keepIds: ["D1"], removableIds: ["D2"]))
        XCTAssertEqual(sim?.review, CategoryReview(keepIds: ["S1"], removableIds: ["S2"]))
        XCTAssertEqual(dup?.assets["D1"], photo("D1"), "i metadati per-id sono ricostruiti dall'indice")
        XCTAssertEqual(relaunched.timestamp(for: .category("exactDuplicates")), stamp,
                       "la freschezza sopravvive al relaunch")
        XCTAssertNil(relaunched.lastPersistenceError)
    }

    // AC-FSE-K1-2 — su uno store IDRATATO aprire la categoria è cache hit: 0
    // invocazioni del rilevatore. Contrasto: su uno store VUOTO (il bug) lo stesso
    // ambiente invoca il rilevatore — così lo «0» è una prova, non una tautologia.
    func test_hydratedStore_opensCategoryWithZeroDetectorCalls() throws {
        let persistence = SpyCategoryResultStore()
        persistence.records["exactDuplicates"] = CategoryResultRecordValue(
            kind: "exactDuplicates", keepIds: ["D1"], removableIds: ["D2"],
            computedAt: Date(timeIntervalSince1970: 1_000)
        )
        let hasher = SpyHasher(digestsById: ["D1": "same", "D2": "same", "U1": "u"])
        let environment = makeEnvironment(hasher: hasher, assets: assets)

        // Store VUOTO (cold relaunch senza idratazione): il rilevatore gira.
        let cold = AnalysisResultsStore(persistence: SpyCategoryResultStore())
        let composed = try openCategory(.exactDuplicates, store: cold, environment: environment)
        XCTAssertGreaterThan(hasher.calls, 0, "senza cache il rilevatore viene invocato (il bug)")
        XCTAssertEqual(composed.review, CategoryReview(keepIds: ["D1"], removableIds: ["D2"]))

        // Store IDRATATO: 0 rilevatori, stesso risultato.
        let warm = AnalysisResultsStore(persistence: persistence)
        try warm.hydrate(assetsById: assetsById)
        let before = hasher.calls
        let served = try openCategory(.exactDuplicates, store: warm, environment: environment)

        XCTAssertEqual(hasher.calls, before, "cache hit: il rilevatore NON è invocato")
        XCTAssertEqual(served.review, composed.review, "servita dalla cache = composta dal rilevatore")
    }

    // AC-FSE-K1-3 — `set` di una categoria è write-through: la persistenza riflette
    // il nuovo valore (solo id) e il timestamp.
    func test_set_writesThroughToPersistence() {
        let persistence = SpyCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        let stamp = Date(timeIntervalSince1970: 7_000)

        store.set(data(keep: ["D1"], removable: ["D2"]), for: .category("exactDuplicates"), at: stamp)

        XCTAssertEqual(persistence.records["exactDuplicates"], CategoryResultRecordValue(
            kind: "exactDuplicates", keepIds: ["D1"], removableIds: ["D2"], libraryToken: nil, computedAt: stamp
        ))
    }

    // AC-FSE-K1-3 — la potatura chirurgica (J2) ripersiste la categoria potata; le
    // categorie non toccate sono ripersistite identiche (mai perse).
    func test_pruneDeleted_writesThroughPrunedRecord() {
        let persistence = SpyCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        let stamp = Date(timeIntervalSince1970: 7_000)
        store.set(data(keep: ["D1"], removable: ["D2"]), for: .category("exactDuplicates"), at: stamp)
        store.set(data(keep: ["S1"], removable: ["S2"]), for: .category("similarPhotos"), at: stamp)

        store.pruneDeleted(ids: ["D2"])

        XCTAssertEqual(persistence.records["exactDuplicates"]?.keepIds, ["D1"])
        XCTAssertEqual(persistence.records["exactDuplicates"]?.removableIds, [], "il record riflette la potatura")
        XCTAssertEqual(persistence.records["similarPhotos"]?.removableIds, ["S2"], "l'altra categoria è intatta")
    }

    // La persistenza SEGUE la memoria: invalidare una categoria la rimuove dal record,
    // `invalidateAll` svuota — un'idratazione futura non resuscita mai uno stantìo.
    func test_invalidate_removesFromPersistence() {
        let persistence = SpyCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)
        store.set(data(keep: [], removable: ["D2"]), for: .category("exactDuplicates"), at: Date())
        store.set(data(keep: [], removable: ["S2"]), for: .category("similarPhotos"), at: Date())

        store.invalidate(.category("exactDuplicates"))
        XCTAssertEqual(persistence.removedKinds, ["exactDuplicates"])
        XCTAssertNil(persistence.records["exactDuplicates"])
        XCTAssertNotNil(persistence.records["similarPhotos"])

        store.invalidateAll()
        XCTAssertEqual(persistence.removeAllCount, 1)
        XCTAssertTrue(persistence.records.isEmpty)
    }

    // Solo le review di categoria sono persistite: aggregati (dashboard/report) e
    // valori non-review sotto `.category` restano in memoria (nessun record spurio).
    func test_nonCategoryValues_areNotPersisted() {
        let persistence = SpyCategoryResultStore()
        let store = AnalysisResultsStore(persistence: persistence)

        store.set(42, for: .dashboard)
        store.set("report", for: .honestReport)
        store.set(7, for: .category("plainNumber"))

        XCTAssertTrue(persistence.upserts.isEmpty, "nessun record per valori non-review")
    }

    // Un errore di persistenza è RIPORTATO (osservabile), mai inghiottito; la memoria
    // resta aggiornata (degrado dichiarato a «solo in memoria»).
    func test_persistenceFailure_isReportedNotSwallowed() {
        let persistence = SpyCategoryResultStore()
        persistence.failure = PersistenceDown()
        let store = AnalysisResultsStore(persistence: persistence)

        store.set(data(keep: ["D1"], removable: ["D2"]), for: .category("exactDuplicates"), at: Date())

        XCTAssertEqual(store.lastPersistenceError?.operation, .upsert)
        XCTAssertEqual(store.lastPersistenceError?.kind, "exactDuplicates")
        let stillCached: CategoryReviewData? = store.value(for: .category("exactDuplicates"))
        XCTAssertNotNil(stillCached, "la memoria resta aggiornata anche se la persistenza fallisce")
    }

    // Idratazione onesta: un id senza metadati nell'indice (asset sparito fra i lanci)
    // è escluso dalla review — mai una riga fantasma; la memoria già popolata vince.
    func test_hydrate_dropsUnknownIds_andNeverOverwritesMemory() throws {
        let persistence = SpyCategoryResultStore()
        persistence.records["exactDuplicates"] = CategoryResultRecordValue(
            kind: "exactDuplicates", keepIds: ["D1"], removableIds: ["D2", "GONE"],
            computedAt: Date(timeIntervalSince1970: 1_000)
        )
        persistence.records["similarPhotos"] = CategoryResultRecordValue(
            kind: "similarPhotos", keepIds: ["S1"], removableIds: ["S2"],
            computedAt: Date(timeIntervalSince1970: 1_000)
        )
        let inMemory = AnalysisResultsStore(persistence: persistence)
        inMemory.set(data(keep: ["S1"], removable: []), for: .category("similarPhotos"), at: Date())

        let fresh = AnalysisResultsStore(persistence: persistence)
        let hydrated = try fresh.hydrate(assetsById: assetsById)
        let dup: CategoryReviewData? = fresh.value(for: .category("exactDuplicates"))
        XCTAssertEqual(hydrated, ["exactDuplicates", "similarPhotos"])
        XCTAssertEqual(dup?.review.removableIds, ["D2"], "l'id senza metadati è escluso")
        XCTAssertNil(dup?.assets["GONE"])

        try inMemory.hydrate(assetsById: assetsById)
        let kept: CategoryReviewData? = inMemory.value(for: .category("similarPhotos"))
        XCTAssertEqual(kept?.review.removableIds, [], "la memoria vince sul record persistito")
    }
}

// MARK: - Confine Apple: stesso giro sullo store SwiftData REALE (relaunch simulato)

#if canImport(SwiftData)
import SwiftData

@available(macOS 14, iOS 17, *)
final class StoreHydrationSwiftDataTests: XCTestCase {

    // AC-FSE-K1-1/2 con l'adapter reale: write-through su SwiftData → store NUOVO
    // sullo STESSO container (relaunch) idratato → identico e senza rilevatori.
    func test_relaunchOnSameContainer_hydratesIdenticallyWithoutDetectors() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CategoryResultRecord.self, configurations: configuration)
        let assets = [photo("D1"), photo("D2"), photo("U1")]
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let hasher = SpyHasher(digestsById: ["D1": "same", "D2": "same", "U1": "u"])
        let environment = makeEnvironment(hasher: hasher, assets: assets)

        // Sessione 1: la scansione compone (rilevatore invocato) e persiste via write-through.
        let session1 = AnalysisResultsStore(persistence: SwiftDataCategoryResultStore(container: container))
        let composed = try openCategory(.exactDuplicates, store: session1, environment: environment)
        XCTAssertGreaterThan(hasher.calls, 0)
        XCTAssertNil(session1.lastPersistenceError, "la persistenza reale deve riuscire")

        // Sessione 2 (relaunch): store nuovo sullo stesso container, idratato.
        let session2 = AnalysisResultsStore(persistence: SwiftDataCategoryResultStore(container: container))
        try session2.hydrate(assetsById: assetsById)
        let before = hasher.calls
        let served = try openCategory(.exactDuplicates, store: session2, environment: environment)

        XCTAssertEqual(hasher.calls, before, "dopo il relaunch: 0 rilevatori")
        XCTAssertEqual(served.review, composed.review, "keep/removable identici ai salvati")
    }
}
#endif
