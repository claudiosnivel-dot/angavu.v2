import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-J7 (censimento C5) — Oracolo del CABLAGGIO del batch resolver nella scansione.
//
// Il port `handleResolver` (leva 1) era costruito in `AppEnvironment.live()` ma nessun
// consumatore lo invocava: la fase pesante risolveva i byte per-asset via
// `byteResolver.byteSize(forLocalIdentifier:)` → 25k fetch singoli. Qui si prova che la
// fase `resolvingSizes` della scansione (`LibraryFiguresReader.resolve`) ora chiede gli
// handle IN BATCH — una sola richiesta per l'intero gruppo, non una per asset — e che il
// byte è davvero risolto DAL handle (riuso reale, non un resolve-and-discard).
//
//   • AC-FSE-J7-1: dato un resolver spione, girando una fase di scansione gli handle sono
//     chiesti in batch (una `resolve` per il gruppo), non uno per asset.
//
// Logica di cablaggio pura (Features + fake dei port): gira in CI, nessun device.

// MARK: - Spie e fake dei port

/// Resolver-spia: conta le chiamate `resolve` e gli id di ciascuna. Una scansione
/// cablata deve chiamarlo UNA volta per l'intero gruppo (il chunking è interno
/// all'adapter reale), mai una volta per asset.
private final class SpyHandleResolver: AssetHandleResolving {
    private(set) var resolveCallCount = 0
    private(set) var idsPerCall: [[String]] = []

    func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles {
        resolveCallCount += 1
        idsPerCall.append(localIdentifiers)
        return ResolvedAssetHandles(localIdentifiers.map { FakeHandle($0) })
    }
}

private final class FakeHandle: AssetHandle {
    let assetLocalIdentifier: String
    init(_ id: String) { self.assetLocalIdentifier = id }
}

/// Byte resolver-spia che distingue i due percorsi: quanti byte sono risolti DAL handle
/// (riuso FSE-J7) contro quanti per id (fetch singolo). Il cablaggio corretto usa il
/// percorso a handle per ogni asset risolto in batch.
private final class PathSpyByteResolver: AssetByteSizeResolving {
    private(set) var byHandleIDs: [String] = []
    private(set) var byIdentifierIDs: [String] = []

    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        byIdentifierIDs.append(localIdentifier)
        return .exact(bytes: 100)
    }

    func byteSize(for handle: AssetHandle, fallbackEstimate: Int64) -> ByteSize {
        byHandleIDs.append(handle.assetLocalIdentifier)
        return .exact(bytes: 100)
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

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

private func makeEnvironment(
    assets: [LibraryAsset],
    byteResolver: any AssetByteSizeResolving,
    handleResolver: any AssetHandleResolving
) -> AppEnvironment {
    let index = StubIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: byteResolver,
        handleResolver: handleResolver,
        deviceStorage: FakeDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

// MARK: - Test

final class BatchResolverWiringTests: XCTestCase {

    // AC-FSE-J7-1 — la fase di scansione chiede gli handle IN BATCH: una sola `resolve`
    // per l'intero gruppo, non una per asset.
    func test_scanResolvesHandlesInBatch_oneRequestForTheGroup() {
        let assets = [photo("A"), photo("B"), photo("C"), photo("D")]
        let handleSpy = SpyHandleResolver()
        let env = makeEnvironment(
            assets: assets,
            byteResolver: PathSpyByteResolver(),
            handleResolver: handleSpy
        )

        let outcome = LibraryFiguresReader.resolve(from: env, cancellation: CancellationToken())
        guard case .completed = outcome else {
            return XCTFail("la scansione dei byte deve completare, esito: \(outcome)")
        }

        // UNA sola richiesta di risoluzione per l'intero gruppo, non 4 (una per asset).
        XCTAssertEqual(handleSpy.resolveCallCount, 1, "gli handle vanno chiesti in batch, non per asset")
        // Quella singola richiesta copre tutti gli id del gruppo, ognuno una volta.
        XCTAssertEqual(handleSpy.idsPerCall.first.map(Set.init), Set(["A", "B", "C", "D"]))
        XCTAssertEqual(handleSpy.idsPerCall.first?.count, assets.count, "nessun id duplicato né mancante")
    }

    // Il riuso è REALE: ogni byte è risolto DAL handle risolto in batch, mai per id
    // (nessun fetch singolo) — l'handle non è risolto e buttato.
    func test_bytesResolvedFromBatchHandle_notPerIdentifier() {
        let assets = [photo("A"), photo("B"), photo("C")]
        let byteSpy = PathSpyByteResolver()
        let env = makeEnvironment(
            assets: assets,
            byteResolver: byteSpy,
            handleResolver: SpyHandleResolver()
        )

        _ = LibraryFiguresReader.resolve(from: env, cancellation: CancellationToken())

        XCTAssertEqual(Set(byteSpy.byHandleIDs), Set(["A", "B", "C"]), "ogni byte risolto dal handle in batch")
        XCTAssertTrue(byteSpy.byIdentifierIDs.isEmpty, "nessun fetch singolo per id quando l'handle è risolto")
    }

    // Un asset NON risolto in batch (assente dalla mappa) ricade sul fetch per id: mai un
    // handle finto, nessuna perdita di correttezza. Prova col null-object di default.
    func test_unresolvedAsset_fallsBackToIdentifierPath() {
        let assets = [photo("A"), photo("B")]
        let byteSpy = PathSpyByteResolver()
        // Resolver vuoto (default del grafo non-cablato): nessun handle risolto.
        let env = makeEnvironment(
            assets: assets,
            byteResolver: byteSpy,
            handleResolver: EmptyAssetHandleResolver()
        )

        _ = LibraryFiguresReader.resolve(from: env, cancellation: CancellationToken())

        XCTAssertTrue(byteSpy.byHandleIDs.isEmpty, "nessun handle disponibile → nessun percorso a handle")
        XCTAssertEqual(Set(byteSpy.byIdentifierIDs), Set(["A", "B"]), "fallback per id, comportamento pre-cablaggio")
    }
}
