import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// Guscio UI — schermata «Comprimi video»: la sorgente dei candidati produce SOLO
// video reali dall'indice, coi byte veri (exact/estimated marcato), ordinati
// grande→piccolo. Un errore d'indice è propagato (mai una lista vuota finta).

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct StubEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct StubDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

/// Risolutore che restituisce byte esatti per gli id nel dizionario, altrimenti
/// degrada a `estimated(fallback)` — così si copre la marcatura `isSizeEstimated`.
private struct MapByteResolver: AssetByteSizeResolving {
    let exact: [String: Int64]
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        if let bytes = exact[localIdentifier] { return .exact(bytes: bytes) }
        return .estimated(bytes: fallbackEstimate)
    }
}

private struct StubIndex: AssetIndexReading, AssetIndexWriting {
    let assetsToReturn: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { assetsToReturn }
    func count() throws -> Int { assetsToReturn.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct ThrowingIndex: AssetIndexReading, AssetIndexWriting {
    struct Boom: Error {}
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { throw Boom() }
    func count() throws -> Int { throw Boom() }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private func video(_ id: String, pixels: Int) -> LibraryAsset {
    LibraryAsset(id: id, kind: .video, pixelSize: PixelSize(width: pixels, height: 1),
                 creationDate: nil, subtypes: [])
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: nil, subtypes: [])
}

private func makeEnvironment<Index: AssetIndexReading & AssetIndexWriting>(
    index: Index,
    exact: [String: Int64] = [:]
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(),
        enumerator: StubEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(exact: exact),
        deviceStorage: StubDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

final class CompressionCandidateSourceTests: XCTestCase {

    // Solo i video sono candidati: le foto non compaiono mai.
    func test_onlyVideosAreCandidates() throws {
        let env = makeEnvironment(
            index: StubIndex(assetsToReturn: [video("V1", pixels: 100), photo("P1")]),
            exact: ["V1": 900]
        )
        let candidates = try CompressionCandidateSource.candidates(from: env)
        XCTAssertEqual(candidates.map(\.id), ["V1"], "solo il video, mai la foto")
    }

    // Ordine grande→piccolo, tie-break per id crescente; byte VERI dal risolutore.
    func test_orderedBySizeDescendingThenId() throws {
        let env = makeEnvironment(
            index: StubIndex(assetsToReturn: [
                video("V_small", pixels: 1),   // estimated fallback = 1*1*2 = 2
                video("V_mid", pixels: 100),   // exact 5000
                video("V_big", pixels: 100)    // exact 5000 → tie con V_mid
            ]),
            exact: ["V_big": 5000, "V_mid": 5000]
        )
        let candidates = try CompressionCandidateSource.candidates(from: env)
        XCTAssertEqual(candidates.map(\.id), ["V_big", "V_mid", "V_small"],
                       "grande→piccolo; a parità l'id crescente")
        XCTAssertEqual(candidates.map(\.originalBytes), [5000, 5000, 2])
    }

    // La marcatura `isSizeEstimated` riflette la fonte: exact vs stima.
    func test_marksEstimatedSizeHonestly() throws {
        let env = makeEnvironment(
            index: StubIndex(assetsToReturn: [video("V_exact", pixels: 100), video("V_est", pixels: 3)]),
            exact: ["V_exact": 4000]
        )
        let candidates = try CompressionCandidateSource.candidates(from: env)
        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        XCTAssertEqual(byId["V_exact"]?.isSizeEstimated, false)
        XCTAssertEqual(byId["V_est"]?.isSizeEstimated, true, "byte stimati vanno marcati")
    }

    // Un errore di lettura dell'indice è propagato: mai una lista vuota spacciata
    // per «nessun video».
    func test_indexErrorIsPropagated() {
        let env = makeEnvironment(index: ThrowingIndex())
        XCTAssertThrowsError(try CompressionCandidateSource.candidates(from: env))
    }
}
