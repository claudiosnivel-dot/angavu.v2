import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-B2 — Oracolo del RIUSO dei byte fra categorie: i byte risolti una volta (fase
// `resolvingSizes` della scansione) sono riusati dalle sorgenti di categoria invece di
// essere ri-risolti sull'intera libreria a ogni schermata (FAST-SCAN-ENGINE-PLAN §1.3).
//
//   • AC-FSE-B2-1: dopo una scansione che ha risolto i byte, comporre «duplicati» e
//     «grandi/vecchi» NON invoca una nuova risoluzione base per gli asset già noti
//     (contatore del resolver base = 0 sul secondo uso), provato con un base spione.
//   • AC-FSE-B2-2: un asset nuovo (non pre-risolto) è risolto on-demand UNA sola volta,
//     mai un valore mancante spacciato per 0.
//
// Logica PURA (Domain/Features + decoratore Data senza piattaforma): gira in CI.

// MARK: - Base spione + fake dei port richiesti

/// Resolver base spione: conta le risoluzioni REALI per id. È ciò che il decoratore
/// cachante deve evitare di reinvocare quando i byte sono già noti.
private final class SpyByteResolver: AssetByteSizeResolving {
    private(set) var callsPerID: [String: Int] = [:]
    let bytesById: [String: Int64]

    init(bytesById: [String: Int64]) { self.bytesById = bytesById }

    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        callsPerID[localIdentifier, default: 0] += 1
        if let bytes = bytesById[localIdentifier] { return .exact(bytes: bytes) }
        return .estimated(bytes: fallbackEstimate)
    }
}

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

private struct FakeDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

private func makeEnvironment(
    assets: [LibraryAsset],
    byteResolver: any AssetByteSizeResolving
) -> AppEnvironment {
    let index = StubIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: byteResolver,
        deviceStorage: FakeDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

// MARK: - Test

final class SizeReuseAcrossCategoriesTests: XCTestCase {

    // AC-FSE-B2-1 — scansione ha risolto i byte; comporre due categorie non ne
    // ri-risolve nessuno (contatore base = 0 sul secondo uso).
    func test_bytesResolvedByScan_areReusedByCategories_withoutReResolving() throws {
        let assets = [photo("A"), photo("B"), photo("C")]
        let spy = SpyByteResolver(bytesById: ["A": 500, "B": 500, "C": 999])
        let caching = CachingByteSizeResolver(base: spy)
        let env = makeEnvironment(assets: assets, byteResolver: caching)

        // Fase `resolvingSizes` della scansione: ogni asset risolto UNA volta.
        for asset in assets {
            _ = caching.byteSize(forLocalIdentifier: asset.id, fallbackEstimate: 1)
        }
        let afterScan = spy.callsPerID
        XCTAssertEqual(afterScan, ["A": 1, "B": 1, "C": 1], "la scansione risolve ogni asset una volta")

        // Comporre due categorie che leggono i byte dell'intera libreria.
        _ = try CategoryReviewSource.reviewData(for: .exactDuplicates, from: env)
        _ = try CategoryReviewSource.reviewData(for: .largeOldVideos, from: env)

        // Nessuna nuova risoluzione base: le categorie leggono dalla cache condivisa.
        XCTAssertEqual(spy.callsPerID, afterScan, "il secondo uso non deve invocare il resolver base")
        for asset in assets {
            XCTAssertEqual(spy.callsPerID[asset.id], 1, "\(asset.id) risolto esattamente una volta in totale")
        }
    }

    // AC-FSE-B2-2 — un asset NUOVO (non pre-risolto) è risolto on-demand una sola volta,
    // mai un mancante spacciato per 0.
    func test_newAsset_resolvedOnceOnDemand_neverZero() throws {
        let assets = [photo("A"), photo("B"), photo("NEW")]
        let spy = SpyByteResolver(bytesById: ["A": 500, "B": 500, "NEW": 300])
        let caching = CachingByteSizeResolver(base: spy)
        let env = makeEnvironment(assets: assets, byteResolver: caching)

        // La scansione ha risolto solo A e B; NEW è comparso dopo (non in cache).
        _ = caching.byteSize(forLocalIdentifier: "A", fallbackEstimate: 1)
        _ = caching.byteSize(forLocalIdentifier: "B", fallbackEstimate: 1)

        // Una categoria che tocca l'intera libreria incontra NEW.
        _ = try CategoryReviewSource.reviewData(for: .largeOldVideos, from: env)

        XCTAssertEqual(spy.callsPerID["A"], 1, "asset già noto: nessuna nuova risoluzione")
        XCTAssertEqual(spy.callsPerID["B"], 1)
        XCTAssertEqual(spy.callsPerID["NEW"], 1, "nuovo asset risolto on-demand esattamente una volta")

        // Il byte di NEW è un valore reale (>0), mai un mancante spacciato per 0; e
        // rileggerlo è un HIT (nessuna ulteriore risoluzione base).
        let newSize = caching.byteSize(forLocalIdentifier: "NEW", fallbackEstimate: 1)
        XCTAssertGreaterThan(newSize.bytes, 0, "mai un mancante spacciato per 0")
        XCTAssertEqual(spy.callsPerID["NEW"], 1, "la rilettura di NEW è un cache hit")
    }
}
