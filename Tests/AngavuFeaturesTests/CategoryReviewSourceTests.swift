import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// C-1 (POST-DEVICE) — Oracolo della sorgente delle review di categoria.
//
// Prova la mappa categoria→sorgente cablata in `CategoryReviewSource`: date le
// risposte dei port dei rilevatori (hasher SHA-256, feature print, nitidezza,
// qualità) iniettati come FAKE, la review composta ha i keep/removable corretti e la
// preselezione protegge i keep. È logica PURA (nessun device): i detector reali
// (Vision/CryptoKit/Core Image) restano compilati-non-testati (L-COL-006). Il gate
// d'anteprima (T-050) e i normalizzatori di dominio hanno i loro test altrove; qui si
// verifica solo il cablaggio nuovo di C-1.

// MARK: - Fake dei port

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

/// Byte esatti per id (controllo preciso di dimensione/candidatura); ripiego alla stima.
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

/// Hasher fake: digest per id da una mappa; assente → `nil` (asset non verificabile).
private struct FakeHasher: AssetContentHashing {
    let digestsById: [String: String]
    func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        digestsById[asset.id].map(AssetDigest.init)
    }
}

/// Feature print fake: distanza per coppia NON ordinata; assente → `nil`.
private struct FakeFeaturePrinter: FeaturePrinting {
    let distancesByPair: [Set<String>: Float]
    func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float? {
        distancesByPair[Set([lhs.id, rhs.id])]
    }
}

/// dHash fake: valore percettivo per id; assente → `nil` (asset senza dHash → singleton).
private struct FakePerceptualHasher: AssetPerceptualHashing {
    let dHashById: [String: UInt64]
    func dHash(for asset: LibraryAsset) -> UInt64? { dHashById[asset.id] }
}

/// Qualità fake: solo nitidezza (più alta = migliore); assente → 0.
private struct FakeQuality: QualityScoring {
    let sharpnessById: [String: Double]
    func score(for asset: LibraryAsset) throws -> QualityScore {
        QualityScore(sharpness: sharpnessById[asset.id] ?? 0, faceQuality: nil, aesthetics: nil)
    }
}

/// Nitidezza fake: valore per id; assente → `nil` (non misurabile → mai sfocato).
private struct FakeSharpness: SharpnessScoring {
    let sharpnessById: [String: Double]
    func sharpness(for asset: LibraryAsset) throws -> Double? {
        sharpnessById[asset.id]
    }
}

// MARK: - Costruzione ambiente + asset

private func makeEnvironment(
    assets: [LibraryAsset],
    bytesById: [String: Int64] = [:],
    digestsById: [String: String] = [:],
    distancesByPair: [Set<String>: Float] = [:],
    dHashById: [String: UInt64] = [:],
    qualityById: [String: Double] = [:],
    sharpnessById: [String: Double] = [:]
) -> AppEnvironment {
    let index = StubIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(bytesById: bytesById),
        deviceStorage: FakeDeviceStorage(),
        contentHasher: FakeHasher(digestsById: digestsById),
        featurePrinter: FakeFeaturePrinter(distancesByPair: distancesByPair),
        perceptualHasher: FakePerceptualHasher(dHashById: dHashById),
        qualityScorer: FakeQuality(sharpnessById: qualityById),
        sharpnessScorer: FakeSharpness(sharpnessById: sharpnessById),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

private func photo(_ id: String, subtypes: Set<AssetSubtype> = []) -> LibraryAsset {
    LibraryAsset(
        id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
        creationDate: nil, subtypes: subtypes
    )
}

private func video(_ id: String, creationDate: Date?) -> LibraryAsset {
    LibraryAsset(
        id: id, kind: .video, pixelSize: PixelSize(width: 1920, height: 1080),
        creationDate: creationDate, subtypes: []
    )
}

// MARK: - Test

final class CategoryReviewSourceTests: XCTestCase {

    // MARK: Duplicati esatti

    // Stessa dimensione + stesso digest ⇒ cluster; si tiene l'id minore, l'altro
    // removable. Un asset di dimensione UNICA non viene hashato (niente candidato);
    // un asset con digest unico non è mai dichiarato duplicato.
    func test_exactDuplicates_keepsOneRemovesRest() throws {
        let env = makeEnvironment(
            assets: [photo("D2"), photo("D1"), photo("U1"), photo("X1")],
            bytesById: ["D1": 500, "D2": 500, "U1": 500, "X1": 999],
            digestsById: ["D1": "same", "D2": "same", "U1": "unique"] // X1 non hashabile → nil
        )

        let data = try CategoryReviewSource.reviewData(for: .exactDuplicates, from: env)

        XCTAssertEqual(data.review.keepIds, ["D1"], "keep = id minore del cluster (deterministico)")
        XCTAssertEqual(data.review.removableIds, ["D2"], "l'altra copia è removable")
        XCTAssertFalse(data.review.removableIds.contains("U1"), "digest unico: mai duplicato")
        XCTAssertFalse(data.review.removableIds.contains("X1"), "dimensione unica: mai hashato")
    }

    // La preselezione protegge il keep: selezionati solo i removable, mai il keep.
    func test_exactDuplicates_preselectionProtectsKeep() throws {
        let env = makeEnvironment(
            assets: [photo("D1"), photo("D2")],
            bytesById: ["D1": 500, "D2": 500],
            digestsById: ["D1": "same", "D2": "same"]
        )
        let review = try CategoryReviewSource.review(for: .exactDuplicates, from: env)
        let selection = CategorySelectionPolicy.initialSelection(for: review)
        XCTAssertEqual(selection, Set(review.removableIds))
        XCTAssertFalse(selection.contains("D1"), "il keep non è mai preselezionato")
    }

    // MARK: Foto simili

    // FSE-H2 — Il percorso principale è il dHash REALE (vicinanza Hamming, BK-tree), non
    // più il feature print. Due foto entro soglia Hamming ⇒ cluster; si tiene la più
    // nitida (qualità), l'altra removable. Una foto lontana resta singleton e NON compare.
    func test_similarPhotos_keepsBestOfCluster() throws {
        let env = makeEnvironment(
            assets: [photo("P1"), photo("P2"), photo("P3")],
            dHashById: [
                "P1": 0x0000_0000_0000_0000,
                "P2": 0x0000_0000_0000_0003,  // 2 bit da P1 → simili (≤ 10)
                "P3": 0xFFFF_FFFF_FFFF_FFFF   // 64 bit da P1/P2 → lontana
            ],
            qualityById: ["P1": 0.9, "P2": 0.2, "P3": 0.5]
        )

        let review = try CategoryReviewSource.review(for: .similarPhotos, from: env)

        XCTAssertEqual(review.keepIds, ["P1"], "si tiene la più nitida del cluster")
        XCTAssertEqual(review.removableIds, ["P2"], "l'altra simile è removable")
        XCTAssertFalse(review.keepIds.contains("P3"), "un singleton non è proposto")
        XCTAssertFalse(review.removableIds.contains("P3"))
    }

    // Nessuna coppia simile ⇒ review vuota (nessun singleton spacciato per gruppo).
    func test_similarPhotos_noSimilars_isEmpty() throws {
        let env = makeEnvironment(
            assets: [photo("P1"), photo("P2")],
            dHashById: [
                "P1": 0x0000_0000_0000_0000,
                "P2": 0xFFFF_FFFF_FFFF_FFFF   // 64 bit di distanza → oltre soglia
            ],
            qualityById: ["P1": 0.5, "P2": 0.5]
        )
        let review = try CategoryReviewSource.review(for: .similarPhotos, from: env)
        XCTAssertTrue(review.keepIds.isEmpty)
        XCTAssertTrue(review.removableIds.isEmpty)
    }

    // Un asset senza dHash (non calcolabile on-device) resta singleton: mai dichiarato
    // simile per costruzione, anche accanto a una coppia realmente simile.
    func test_similarPhotos_assetWithoutDHash_staysSingleton() throws {
        let env = makeEnvironment(
            assets: [photo("P1"), photo("P2"), photo("X")],
            dHashById: [
                "P1": 0x0000_0000_0000_0000,
                "P2": 0x0000_0000_0000_0001   // 1 bit → simili
                // "X" assente → dHash nil → singleton, mai un falso "simile"
            ],
            qualityById: ["P1": 0.9, "P2": 0.2]
        )
        let review = try CategoryReviewSource.review(for: .similarPhotos, from: env)
        XCTAssertEqual(review.keepIds, ["P1"])
        XCTAssertEqual(review.removableIds, ["P2"])
        XCTAssertFalse(review.keepIds.contains("X"))
        XCTAssertFalse(review.removableIds.contains("X"))
    }

    // MARK: Foto sfocate

    // Sotto soglia ⇒ removable; nitida ⇒ esclusa; nitidezza non misurabile ⇒ mai
    // sfocata; i video sono esclusi a monte.
    func test_blurryPhotos_belowThresholdOnly() throws {
        let env = makeEnvironment(
            assets: [photo("B1"), photo("S1"), photo("N1"), video("V1", creationDate: nil)],
            sharpnessById: ["B1": 0.1, "S1": 0.9] // N1 assente → nil; V1 è video
        )

        let review = try CategoryReviewSource.review(for: .blurryPhotos, from: env)

        XCTAssertTrue(review.keepIds.isEmpty, "sfocate = eliminazione diretta, nessun keep")
        XCTAssertEqual(review.removableIds, ["B1"], "solo la foto sotto soglia")
    }

    // MARK: Video grandi e vecchi

    // Grande (≥100 MB) E vecchio (>1 anno) ⇒ removable; recente o piccolo ⇒ escluso;
    // una foto non entra mai (solo video).
    func test_largeOldVideos_conjunctiveThresholds() throws {
        let big: Int64 = 200 * 1024 * 1024   // 200 MB
        let small: Int64 = 50 * 1024 * 1024  // 50 MB
        let env = makeEnvironment(
            assets: [
                video("V_bigOld", creationDate: .distantPast),
                video("V_bigRecent", creationDate: Date()),
                video("V_smallOld", creationDate: .distantPast),
                photo("P_bigOld")
            ],
            bytesById: ["V_bigOld": big, "V_bigRecent": big, "V_smallOld": small, "P_bigOld": big]
        )

        let review = try CategoryReviewSource.review(for: .largeOldVideos, from: env)

        XCTAssertTrue(review.keepIds.isEmpty, "eliminazione diretta, nessun keep")
        XCTAssertEqual(review.removableIds, ["V_bigOld"], "solo il video grande E vecchio")
    }

    // MARK: Progresso determinato (seam D-2)

    // Le categorie a motore (qui duplicati) riportano X/N reale e monotòno fino al
    // completamento: la barra determinata può accendersi onestamente (mai una frazione
    // fabbricata).
    func test_exactDuplicates_reportsDeterminateProgress() throws {
        let env = makeEnvironment(
            assets: [photo("D1"), photo("D2"), photo("D3")],
            bytesById: ["D1": 500, "D2": 500, "D3": 500],
            digestsById: ["D1": "a", "D2": "a", "D3": "a"]
        )
        var progresses: [AnalysisProgress] = []
        _ = try CategoryReviewSource.reviewData(for: .exactDuplicates, from: env) { progresses.append($0) }

        XCTAssertEqual(progresses.last?.total, 3, "il totale è il numero di candidati hashati")
        XCTAssertEqual(progresses.last?.processed, 3, "a fine corsa tutti processati")
        XCTAssertTrue(progresses.last?.isComplete == true)
    }

    // MARK: Metadati e allCases

    // I metadati per-id coprono gli asset coinvolti (per miniature/etichette, A-3).
    func test_reviewData_indexesInvolvedAssets() throws {
        let env = makeEnvironment(
            assets: [photo("D1"), photo("D2")],
            bytesById: ["D1": 500, "D2": 500],
            digestsById: ["D1": "same", "D2": "same"]
        )
        let data = try CategoryReviewSource.reviewData(for: .exactDuplicates, from: env)
        XCTAssertNotNil(data.assets["D1"])
        XCTAssertNotNil(data.assets["D2"])
    }

    // Tutte le categorie hanno testi non vuoti e chiavi di cache distinte (rawValue).
    func test_allCategories_haveHonestTextsAndDistinctKeys() {
        let all = CleanupCategory.allCases
        XCTAssertEqual(all.count, 5)
        for category in all {
            XCTAssertFalse(category.title.isEmpty, "titolo non vuoto per \(category)")
            XCTAssertFalse(category.subtitle.isEmpty, "sottotitolo non vuoto per \(category)")
            XCTAssertFalse(category.symbol.isEmpty, "simbolo non vuoto per \(category)")
        }
        let rawValues = Set(all.map(\.rawValue))
        XCTAssertEqual(rawValues.count, all.count, "rawValue univoci ⇒ chiavi di cache distinte")
    }
}
