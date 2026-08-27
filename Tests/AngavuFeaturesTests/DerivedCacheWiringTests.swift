import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// FSE-E3 — Oracolo del cablaggio get-or-compute della cache dei derivati.
//
// AC-FSE-E3-1: un feature print già in cache (versione corrente) NON viene ricalcolato
//   quando il clustering ne chiede il vettore (contatore di calcolo = 0), è letto dalla
//   cache derivata.
// AC-FSE-E3-2: un cambio libreria segnalato dall'observer per A invalida il derivato di
//   A → il prossimo uso ricalcola (mai un vettore stantìo).
//
// Tutto puro (nessun Vision, nessun PhotoKit): il produttore e lo store sono fake che
// contano i calcoli. Il produttore reale (Vision) e il risolutore di versione reale
// (PhotoKit) sono device-only (L-COL-006), qui non toccati.

final class DerivedCacheWiringTests: XCTestCase {

    // MARK: - Doppioni

    /// Store dei derivati in memoria: un dizionario per id, con la stessa semantica di
    /// upsert-per-id / remove / removeAll dello store SwiftData reale (FSE-E2).
    private final class FakeDerivedStore: DerivedResultStoring {
        private(set) var records: [String: (key: DerivedKey, value: DerivedRecordValue)] = [:]

        init(seed: [DerivedKey: DerivedRecordValue] = [:]) {
            for (key, value) in seed { records[key.id] = (key, value) }
        }

        func loadAll() throws -> [DerivedKey: DerivedRecordValue] {
            var result: [DerivedKey: DerivedRecordValue] = [:]
            for (_, entry) in records { result[entry.key] = entry.value }
            return result
        }

        func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws {
            for (key, value) in entries { records[key.id] = (key, value) }
        }

        func remove(ids: [String]) throws {
            for id in ids { records.removeValue(forKey: id) }
        }

        func removeAll() throws { records.removeAll() }
    }

    /// Produttore di vettori che CONTA i calcoli: ogni chiamata reale (miss) incrementa
    /// il contatore. Un HIT in cache non deve mai arrivarci → contatore invariato.
    private final class CountingVectorProducer: FeaturePrintVectorProducing {
        private(set) var computeCount = 0
        var stub: (String) -> Data? = { id in Data("vec-\(id)".utf8) }

        func vector(for asset: LibraryAsset) throws -> Data? {
            computeCount += 1
            return stub(asset.id)
        }
    }

    /// Risolutore di versione deterministico e iniettabile: cambiare la versione di un id
    /// simula un contenuto modificato (senza PhotoKit).
    private final class StubVersioning: AssetContentVersioning {
        var versions: [String: String]
        init(_ versions: [String: String]) { self.versions = versions }
        func contentVersion(for asset: LibraryAsset) -> String { versions[asset.id] ?? "1" }
    }

    private func asset(_ id: String) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
    }

    // MARK: - AC-FSE-E3-1 — cache HIT ⇒ nessun ricalcolo

    func test_cachedFeaturePrint_isReadFromCache_notRecomputed() throws {
        // GIVEN un feature print già persistito per A alla versione corrente.
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let persistedVector = Data("persisted-A".utf8)
        let store = FakeDerivedStore(seed: [keyA: DerivedRecordValue(featurePrint: persistedVector)])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let base = CountingVectorProducer()
        let caching = CachingFeaturePrintVectors(
            base: base,
            cache: cache,
            versioning: StubVersioning(["A": "1"])
        )

        // WHEN il clustering chiede il vettore di A.
        let vector = try caching.vector(for: asset("A"))

        // THEN è quello in cache e il produttore di base NON è stato chiamato.
        XCTAssertEqual(vector, persistedVector)
        XCTAssertEqual(base.computeCount, 0, "un vettore valido in cache non si ricalcola")
    }

    func test_cacheMiss_computesOnce_thenServesFromCache() throws {
        // GIVEN nessun derivato persistito per B.
        let store = FakeDerivedStore()
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [DerivedKey(id: "B", contentVersion: "1")])

        let base = CountingVectorProducer()
        let caching = CachingFeaturePrintVectors(
            base: base,
            cache: cache,
            versioning: StubVersioning(["B": "1"])
        )

        // WHEN si chiede due volte il vettore di B.
        let first = try caching.vector(for: asset("B"))
        let second = try caching.vector(for: asset("B"))

        // THEN calcolato UNA volta (miss), poi servito dalla cache + persistito.
        XCTAssertEqual(first, Data("vec-B".utf8))
        XCTAssertEqual(second, first)
        XCTAssertEqual(base.computeCount, 1, "il miss calcola una volta sola; il secondo uso è HIT")
        XCTAssertEqual(store.records["B"]?.value.featurePrint, first, "il vettore calcolato è persistito")
    }

    func test_staleVersion_isNotServed_recomputes() throws {
        // GIVEN un feature print persistito per A alla versione "1"...
        let store = FakeDerivedStore(seed: [
            DerivedKey(id: "A", contentVersion: "1"): DerivedRecordValue(featurePrint: Data("old".utf8))
        ])
        let cache = DerivedResultCache(store: store)
        // ...ma l'asset corrente è alla versione "2" (contenuto cambiato).
        let currentKey = DerivedKey(id: "A", contentVersion: "2")
        try cache.warm(current: [currentKey])

        let base = CountingVectorProducer()
        base.stub = { _ in Data("fresh".utf8) }
        let caching = CachingFeaturePrintVectors(
            base: base,
            cache: cache,
            versioning: StubVersioning(["A": "2"])
        )

        let vector = try caching.vector(for: asset("A"))

        XCTAssertEqual(vector, Data("fresh".utf8), "un derivato stantìo non viene mai servito")
        XCTAssertEqual(base.computeCount, 1)
    }

    // MARK: - merge preserva gli altri campi

    func test_merge_preservesOtherDerivedFields() throws {
        // GIVEN A valido con un digest già in cache, ma senza feature print.
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let store = FakeDerivedStore(seed: [keyA: DerivedRecordValue(digest: "sha-A")])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let base = CountingVectorProducer()
        let caching = CachingFeaturePrintVectors(
            base: base,
            cache: cache,
            versioning: StubVersioning(["A": "1"])
        )

        _ = try caching.vector(for: asset("A"))

        // THEN il feature print è scritto SENZA cancellare il digest esistente.
        XCTAssertEqual(store.records["A"]?.value.digest, "sha-A", "il merge non sovrascrive gli altri campi")
        XCTAssertEqual(store.records["A"]?.value.featurePrint, Data("vec-A".utf8))
    }

    // MARK: - AC-FSE-E3-2 — l'observer invalida per-asset

    func test_libraryChange_invalidatesDerivedPerAsset_forcingRecompute() throws {
        // GIVEN A e B validi in cache.
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let keyB = DerivedKey(id: "B", contentVersion: "1")
        let store = FakeDerivedStore(seed: [
            keyA: DerivedRecordValue(featurePrint: Data("A".utf8)),
            keyB: DerivedRecordValue(featurePrint: Data("B".utf8))
        ])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA, keyB])

        let base = CountingVectorProducer()
        let caching = CachingFeaturePrintVectors(
            base: base,
            cache: cache,
            versioning: StubVersioning(["A": "1", "B": "1"])
        )

        // WHEN l'observer segnala che A è cambiato.
        let sink = StoreInvalidatingLibrarySink(store: AnalysisResultsStore(), derivedCache: cache)
        sink.didObserve(IndexDelta(changed: [asset("A")]))

        // THEN il derivato STANTÌO di A è rimosso subito (prima di qualunque ricalcolo);
        // quello di B, non toccato dal delta, resta.
        XCTAssertNil(store.records["A"], "il derivato stantìo di A è rimosso dallo store")
        XCTAssertEqual(store.records["B"]?.value.featurePrint, Data("B".utf8), "B non è invalidato")

        // Il prossimo uso di A ricalcola (mai il vettore stantìo) e ripersiste il FRESCO.
        let recomputedA = try caching.vector(for: asset("A"))
        XCTAssertEqual(base.computeCount, 1, "A è stato invalidato → ricalcolo")
        XCTAssertEqual(recomputedA, Data("vec-A".utf8), "il vettore servito è quello fresco, non lo stantìo")
        XCTAssertEqual(store.records["A"]?.value.featurePrint, Data("vec-A".utf8), "il fresco è ripersistito")

        // B resta un HIT: nessun ricalcolo aggiuntivo.
        let cachedB = try caching.vector(for: asset("B"))
        XCTAssertEqual(cachedB, Data("B".utf8))
        XCTAssertEqual(base.computeCount, 1, "B non è toccato dal delta → HIT, nessun ricalcolo")
    }

    func test_libraryChange_removedAsset_invalidatesItsDerived() throws {
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let store = FakeDerivedStore(seed: [keyA: DerivedRecordValue(featurePrint: Data("A".utf8))])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let sink = StoreInvalidatingLibrarySink(store: AnalysisResultsStore(), derivedCache: cache)
        sink.didObserve(IndexDelta(removed: ["A"]))

        XCTAssertNil(store.records["A"], "un asset rimosso non deve lasciare un derivato orfano")
        XCTAssertNil(cache.validValue(for: keyA), "la cache in memoria non serve più A")
    }

    func test_sinkWithoutDerivedCache_stillInvalidatesResults() {
        // Retro-compatibilità: senza cache derivata il sink resta quello di D-1.
        let results = AnalysisResultsStore()
        results.set(1, for: .dashboard)
        StoreInvalidatingLibrarySink(store: results).didObserve(IndexDelta(removed: ["x"]))
        XCTAssertTrue(results.isEmpty)
    }
}
