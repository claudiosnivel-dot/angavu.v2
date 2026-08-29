import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// FSE-J6 (censimento C3) — Oracolo del cablaggio del DIGEST nella scansione reale.
//
// AC-FSE-J6-1: dato uno store di derivati con valori validi, quando una SECONDA scansione
//   gira, riusa i derivati validi (0 ricalcoli), coerente con FSE-E3. Qui il valore è il
//   digest (SHA-256 dei duplicati esatti): il rilevatore chiede il digest a
//   `environment.contentHasher`, che in `live()` è `CachingContentDigests` (get-or-compute).
// AC-FSE-J6-2 (parte cablabile in CI): la RADICE DI COMPOSIZIONE inietta lo store SwiftData
//   reale + il decoratore cachante — provata in `CompositionRootWiringTests`. La persistenza
//   reale fra lanci resta device-only (§7).
//
// Tutto puro (nessun SwiftData, nessun PhotoKit): store e hasher sono fake che contano i
// calcoli, così l'oracolo gira al confine CI. Fake dedicati a questo file (test double
// locali) per tenere corti i corpi di tipo (type_body_length).

final class DerivedDigestCacheWiringTests: XCTestCase {

    /// Store dei derivati in memoria: stessa semantica di upsert-per-id / remove / removeAll
    /// dello store SwiftData reale (FSE-E2), così la SECONDA scansione legge ciò che la prima
    /// ha persistito.
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

    /// Hasher di digest che CONTA i calcoli reali (letture byte + SHA-256): un HIT in cache
    /// non deve mai arrivarci → contatore invariato.
    private final class CountingDigestHasher: AssetContentHashing {
        private(set) var computeCount = 0
        var stub: (String) -> AssetDigest? = { id in AssetDigest("sha-\(id)") }

        func digest(for asset: LibraryAsset) throws -> AssetDigest? {
            computeCount += 1
            return stub(asset.id)
        }
    }

    /// Versioning deterministico e iniettabile: cambiare la versione di un id simula un
    /// contenuto modificato (senza PhotoKit).
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

    // MARK: - AC-FSE-J6-1

    func test_cachedDigest_isReadFromCache_notRecomputed() throws {
        // GIVEN un digest già persistito per A alla versione corrente.
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let store = FakeDerivedStore(seed: [keyA: DerivedRecordValue(digest: "sha-persisted")])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let base = CountingDigestHasher()
        let caching = CachingContentDigests(base: base, cache: cache, versioning: StubVersioning(["A": "1"]))

        // WHEN il rilevatore dei duplicati chiede il digest di A.
        let digest = try caching.digest(for: asset("A"))

        // THEN è quello in cache e i byte non vengono mai riletti/ri-hashati.
        XCTAssertEqual(digest, AssetDigest("sha-persisted"))
        XCTAssertEqual(base.computeCount, 0, "un digest valido in cache non si ricalcola")
    }

    /// «una SECONDA scansione riusa i derivati validi (0 ricalcoli)»: la prima scansione
    /// popola lo store, la seconda (cache in memoria FRESCA sopra lo STESSO store, come dopo
    /// un cold relaunch) non richiama mai l'hasher di base.
    func test_secondScan_reusesPersistedDigests_zeroRecompute() throws {
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let keyB = DerivedKey(id: "B", contentVersion: "1")
        let store = FakeDerivedStore()
        let versioning = StubVersioning(["A": "1", "B": "1"])

        // PRIMA scansione: store vuoto → due miss, i digest vengono persistiti.
        let firstCache = DerivedResultCache(store: store)
        try firstCache.warm(current: [keyA, keyB])
        let firstBase = CountingDigestHasher()
        let firstScan = CachingContentDigests(base: firstBase, cache: firstCache, versioning: versioning)
        _ = try firstScan.digest(for: asset("A"))
        _ = try firstScan.digest(for: asset("B"))
        XCTAssertEqual(firstBase.computeCount, 2, "la prima scansione calcola entrambi (miss)")
        XCTAssertEqual(store.records["A"]?.value.digest, "sha-A")
        XCTAssertEqual(store.records["B"]?.value.digest, "sha-B")

        // SECONDA scansione: cache NUOVA sopra lo stesso store persistito (cold relaunch),
        // riscaldata con gli stessi asset → nessun ricalcolo, i digest tornano dalla cache.
        let secondCache = DerivedResultCache(store: store)
        try secondCache.warm(current: [keyA, keyB])
        let secondBase = CountingDigestHasher()
        let secondScan = CachingContentDigests(base: secondBase, cache: secondCache, versioning: versioning)
        let digestA = try secondScan.digest(for: asset("A"))
        let digestB = try secondScan.digest(for: asset("B"))

        XCTAssertEqual(digestA, AssetDigest("sha-A"))
        XCTAssertEqual(digestB, AssetDigest("sha-B"))
        XCTAssertEqual(secondBase.computeCount, 0, "la seconda scansione riusa i persistiti: 0 ricalcoli")
    }

    func test_staleDigestVersion_isNotServed_recomputes() throws {
        // Un digest persistito a versione "1" non viene servito se l'asset è a "2".
        let store = FakeDerivedStore(seed: [
            DerivedKey(id: "A", contentVersion: "1"): DerivedRecordValue(digest: "sha-old")
        ])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [DerivedKey(id: "A", contentVersion: "2")])

        let base = CountingDigestHasher()
        base.stub = { _ in AssetDigest("sha-fresh") }
        let caching = CachingContentDigests(base: base, cache: cache, versioning: StubVersioning(["A": "2"]))

        let digest = try caching.digest(for: asset("A"))
        XCTAssertEqual(digest, AssetDigest("sha-fresh"), "un digest stantìo non viene mai servito")
        XCTAssertEqual(base.computeCount, 1)
    }

    func test_nilDigest_isNotPersisted() throws {
        // Un asset non leggibile on-device (`nil`) non viene mai dichiarato duplicato: il
        // `nil` non è persistito (mai un digest fabbricato).
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let store = FakeDerivedStore()
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let base = CountingDigestHasher()
        base.stub = { _ in nil }
        let caching = CachingContentDigests(base: base, cache: cache, versioning: StubVersioning(["A": "1"]))

        XCTAssertNil(try caching.digest(for: asset("A")))
        XCTAssertNil(store.records["A"], "un digest nil non viene mai persistito")
    }

    func test_digestMerge_preservesFeaturePrintOfSameAsset() throws {
        // Il digest scritto non cancella un feature print già in cache per lo stesso id.
        let keyA = DerivedKey(id: "A", contentVersion: "1")
        let store = FakeDerivedStore(seed: [keyA: DerivedRecordValue(featurePrint: Data("fp-A".utf8))])
        let cache = DerivedResultCache(store: store)
        try cache.warm(current: [keyA])

        let caching = CachingContentDigests(
            base: CountingDigestHasher(), cache: cache, versioning: StubVersioning(["A": "1"])
        )
        _ = try caching.digest(for: asset("A"))

        XCTAssertEqual(store.records["A"]?.value.digest, "sha-A")
        XCTAssertEqual(store.records["A"]?.value.featurePrint, Data("fp-A".utf8), "il merge preserva gli altri campi")
    }

    // MARK: - AssetFieldContentVersioning — versioning puro, stabile senza fetch

    private func photo(width: Int, created: Date?) -> LibraryAsset {
        LibraryAsset(
            id: "A",
            kind: .photo,
            pixelSize: PixelSize(width: width, height: 200),
            creationDate: created,
            subtypes: []
        )
    }

    func test_fieldVersioning_stableAcrossUnchangedFields_changesWithPixelSize() {
        let versioning = AssetFieldContentVersioning()
        let created = Date(timeIntervalSinceReferenceDate: 1000)
        let base = photo(width: 100, created: created)
        let same = photo(width: 100, created: created)
        let cropped = photo(width: 80, created: created)

        XCTAssertEqual(versioning.contentVersion(for: base), versioning.contentVersion(for: same),
                       "campi invariati → stessa versione (HIT stabile fra scansioni)")
        XCTAssertNotEqual(versioning.contentVersion(for: base), versioning.contentVersion(for: cropped),
                          "un cambio di dimensioni muove la versione → ricalcolo")
    }
}
