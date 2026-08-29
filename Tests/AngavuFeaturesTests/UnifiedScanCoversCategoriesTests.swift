import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-F1 — «un'unica scansione fa tutto»: oracolo del coordinatore di scansione.
//
// La scansione unificata, dopo indice + byte + residenza, calcola ANCHE i rilevatori
// di categoria come fasi della stessa barra e ne cacha i risultati (chiavi
// `.category(...)`), così aprire una categoria è istantaneo — mai una nuova scansione
// al tap. Qui si prova la LOGICA dietro i port con dei fake (nessun device):
//   • AC-FSE-F1-1: dopo una scansione completa, ogni categoria è in cache; leggere la
//     cache non riesegue alcun rilevatore (contatore = 0 al tap);
//   • AC-FSE-F1-2: una scansione cancellata a metà lascia cachate SOLO le categorie
//     raggiunte; quelle non raggiunte restano fuori (calcolate al tap), mai un parziale
//     spacciato per completo.
// La resa del carosello/titoli di fase durante l'attesa è FSE-F2; il popolamento reale
// della cache da parte della Home è View-level (compilato, non coperto, L-COL-006).

// MARK: - Fake dei port

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    let access: PhotoAccess
    func currentAccess() -> PhotoAccess { access }
    func requestAccess() async -> PhotoAccess { access }
}

private struct StubEnumerator: PhotoAssetEnumerating {
    let raws: [RawEnumeratedAsset]
    func enumerateRawAssets() -> [RawEnumeratedAsset] { raws }
}

private final class RecordingIndex: AssetIndexReading, AssetIndexWriting {
    private(set) var upserted: [LibraryAsset] = []
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { upserted }
    func count() throws -> Int { upserted.count }
    func upsert(_ assets: [LibraryAsset]) throws { upserted.append(contentsOf: assets) }
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

/// Nitidezza spia: conta le misure (lavoro REALE del rilevatore sfocate) e restituisce
/// un valore nitido (> soglia 0.3), così nessuna foto è dichiarata sfocata.
private final class CountingSharpnessScorer: SharpnessScoring {
    private(set) var count = 0
    let value: Double
    init(value: Double) { self.value = value }
    func sharpness(for asset: LibraryAsset) throws -> Double? {
        count += 1
        return value
    }
}

/// Hasher che CANCELLA il token della scansione alla prima chiamata (durante la fase
/// dei duplicati), per provare la cancellazione a metà delle fasi rilevatore. Restituisce
/// `nil` (nessun digest) → nessun duplicato dichiarato.
private final class CancellingContentHasher: AssetContentHashing {
    private let token: CancellationToken
    private(set) var count = 0
    init(token: CancellationToken) { self.token = token }
    func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        count += 1
        token.cancel()
        return nil
    }
}

private func photo(_ id: String) -> RawEnumeratedAsset {
    RawEnumeratedAsset(
        localIdentifier: id,
        mediaTypeRawValue: 1, // image
        pixelWidth: 100,
        pixelHeight: 100,
        creationDate: nil,
        isScreenshot: false,
        isLivePhoto: false
    )
}

private func makeEnv(
    access: PhotoAccess,
    raws: [RawEnumeratedAsset],
    index: RecordingIndex,
    sharpnessScorer: any SharpnessScoring,
    contentHasher: any AssetContentHashing
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(raws: raws),
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: StubDeviceStorage(),
        contentHasher: contentHasher,
        sharpnessScorer: sharpnessScorer,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

final class UnifiedScanCoversCategoriesTests: XCTestCase {

    // AC-FSE-F1-1 (rivisto dopo il device-test) — la scansione unificata calcola e cacha
    // le categorie ECONOMICHE in una passata (aprirle è istantaneo, 0 rilevatori al tap);
    // i rilevatori per-foto PESANTI (simili, sfocate) sono DIFFERITI — non calcolati
    // eager (evitano il crash on-device), si calcolano al primo tap.
    func test_unifiedScanCachesCheapCategories_defersHeavyDetectors() async throws {
        let index = RecordingIndex()
        let sharpness = CountingSharpnessScorer(value: 0.9)
        let env = makeEnv(
            access: .full,
            raws: [photo("A"), photo("B"), photo("C")],
            index: index,
            sharpnessScorer: sharpness,
            contentHasher: NoContentHasher()
        )
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())
        XCTAssertEqual(final, .completed(indexed: 3, partialCount: false))

        // Le categorie EAGER (economiche/limitate) sono cachate dalla scansione.
        for category in CleanupCategory.allCases where category.runsInUnifiedScan {
            XCTAssertNotNil(vm.categoryResults[category],
                            "la categoria eager \(category) deve essere calcolata dalla scansione")
        }
        // Le categorie DIFFERITE (per-foto pesanti) NON sono cachate: si calcolano al tap.
        for category in CleanupCategory.allCases where !category.runsInUnifiedScan {
            XCTAssertNil(vm.categoryResults[category],
                         "la categoria differita \(category) non è calcolata eager (evita il crash)")
        }
        // Il rilevatore pesante (nitidezza/sfocate) NON è mai partito durante la scansione.
        XCTAssertEqual(sharpness.count, 0, "il rilevatore differito non gira nella scansione")

        // La Home popola la cache sopra le view (stesso cablaggio di HomeView).
        let store = AnalysisResultsStore()
        for (category, data) in vm.categoryResults {
            store.set(data, for: .category(category.rawValue))
        }

        // Aprire una categoria EAGER = leggere la cache: valore presente, nessuna composizione.
        for category in CleanupCategory.allCases where category.runsInUnifiedScan {
            let cached: CategoryReviewData? = store.value(for: .category(category.rawValue))
            XCTAssertNotNil(cached, "la categoria eager \(category) deve essere in cache dopo la scansione")
        }
        // Una categoria DIFFERITA non è in cache → al tap si compone dal vivo (cache-miss),
        // e il rilevatore gira davvero (prova che il differimento non salta il lavoro,
        // lo sposta al tap).
        let deferredCached: CategoryReviewData? = store.value(for: .category(CleanupCategory.blurryPhotos.rawValue))
        XCTAssertNil(deferredCached, "una categoria differita non è pre-cachata")
        _ = try CategoryReviewSource.reviewData(for: .blurryPhotos, from: env)
        XCTAssertGreaterThan(sharpness.count, 0, "al tap la categoria differita invoca il rilevatore")
    }

    // AC-FSE-F1-2 — una scansione cancellata a metà delle fasi rilevatore cacha SOLO le
    // categorie raggiunte; le non raggiunte restano fuori (mai un parziale spacciato per
    // completo → verranno calcolate al tap).
    func test_cancelledMidDetectors_cachesReachedCategoriesOnly() async {
        let index = RecordingIndex()
        let token = CancellationToken()
        // Cancella durante la fase DUPLICATI (2ª fase rilevatore): screenshot è già fatto.
        let hasher = CancellingContentHasher(token: token)
        let sharpness = CountingSharpnessScorer(value: 0.9)
        let env = makeEnv(
            access: .full,
            raws: [photo("A"), photo("B"), photo("C")],
            index: index,
            sharpnessScorer: sharpness,
            contentHasher: hasher
        )
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: token)

        guard case .cancelled = final else {
            return XCTFail("atteso stato cancelled, ottenuto \(final)")
        }
        // L'hasher è stato invocato (la fase duplicati è davvero partita e ha cancellato).
        XCTAssertGreaterThan(hasher.count, 0)
        // La categoria raggiunta PRIMA del punto di cancellazione è cachata.
        XCTAssertNotNil(vm.categoryResults[.screenshots],
                        "una categoria completata prima della cancellazione resta cachata")
        // Le categorie DOPO il punto di cancellazione restano fuori: verranno calcolate
        // al tap, mai un parziale spacciato per completo.
        XCTAssertNil(vm.categoryResults[.similarPhotos],
                     "una categoria non raggiunta non deve essere cachata")
        XCTAssertNil(vm.categoryResults[.blurryPhotos])
        XCTAssertNil(vm.categoryResults[.largeOldVideos])
        // Il rilevatore di nitidezza (fase successiva alla cancellazione) non è mai partito.
        XCTAssertEqual(sharpness.count, 0,
                       "nessun rilevatore oltre il punto di cancellazione deve girare")
    }
}
