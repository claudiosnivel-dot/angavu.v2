import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-I1 — Oracolo del cablaggio del ripristino al lancio.
//
// Prova la LOGICA dietro i port (nessun device, nessuna SwiftUI — HomeView resta
// compilata-non-testata, L-COL-006):
//   • il coordinatore consulta l'indice persistito e decide RESTORE quando non è vuoto;
//   • AC-FSE-I1-3: in un ripristino, aprire una categoria si compone ON-TAP dall'indice
//     persistito (o dalla cache), MAI una nuova scansione unificata forzata — la scansione
//     ri-enumera la libreria e riscrive l'indice; l'apertura di categoria no.

// MARK: - Fake dei port

/// Indice seminato + spia della scrittura: legge gli asset seminati, e conta upsert/remove
/// (una scansione unificata riscriverebbe l'indice; un'apertura di categoria no).
private final class SeededSpyIndex: AssetIndexReading, AssetIndexWriting {
    private(set) var stored: [LibraryAsset]
    private(set) var reads = 0
    private(set) var upsertCalls = 0
    private(set) var removeCalls = 0

    init(_ stored: [LibraryAsset]) { self.stored = stored }

    func assets(matching query: AssetQuery) throws -> [LibraryAsset] {
        reads += 1
        return stored
    }
    func count() throws -> Int { stored.count }
    func upsert(_ assets: [LibraryAsset]) throws {
        upsertCalls += 1
        stored.append(contentsOf: assets)
    }
    func remove(ids: [String]) throws { removeCalls += 1 }
}

/// Indice che LANCIA sulla lettura: prova che una lettura fallita → `.fresh`.
private struct FailingIndex: AssetIndexReading {
    struct Boom: Error {}
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { throw Boom() }
    func count() throws -> Int { throw Boom() }
}

/// Enumerator spia: conta le enumerazioni della libreria (punto d'ingresso della
/// scansione unificata). In un ripristino con apertura di categoria deve restare a 0.
private final class SpyEnumerator: PhotoAssetEnumerating {
    private(set) var calls = 0
    func enumerateRawAssets() -> [RawEnumeratedAsset] {
        calls += 1
        return []
    }
}

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
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

private func screenshot(_ id: String) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .photo,
        pixelSize: PixelSize(width: 100, height: 100),
        creationDate: nil,
        subtypes: [.screenshot]
    )
}

private func makeEnv(index: SeededSpyIndex, enumerator: any PhotoAssetEnumerating) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(),
        enumerator: enumerator,
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: StubDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

final class LaunchRestoreWiringTests: XCTestCase {

    // Il coordinatore consulta l'indice persistito: non vuoto → RESTORE (AC-FSE-I1-1 al
    // livello di cablaggio, speculare all'oracolo di dominio).
    func test_coordinator_nonEmptyIndex_decidesRestore() {
        let index = SeededSpyIndex([screenshot("A"), screenshot("B")])
        let coordinator = LaunchRestoreCoordinator(indexReader: index)
        XCTAssertEqual(coordinator.decision(), .restore)
    }

    // Indice vuoto → FRESH (AC-FSE-I1-2 al livello di cablaggio).
    func test_coordinator_emptyIndex_decidesFresh() {
        let index = SeededSpyIndex([])
        let coordinator = LaunchRestoreCoordinator(indexReader: index)
        XCTAssertEqual(coordinator.decision(), .fresh)
    }

    // Onestà: una lettura dell'indice che fallisce non ripristina su dati illeggibili → FRESH.
    func test_coordinator_readFailure_decidesFresh() {
        let coordinator = LaunchRestoreCoordinator(indexReader: FailingIndex())
        XCTAssertEqual(coordinator.decision(), .fresh)
    }

    // AC-FSE-I1-3 — in un ripristino, aprire una categoria si compone ON-TAP dall'indice
    // persistito: legge l'indice ma NON ri-enumera la libreria né riscrive l'indice (cioè
    // NON avvia una scansione unificata).
    func test_restore_openingCategory_composesOnTap_neverUnifiedScan() throws {
        let index = SeededSpyIndex([screenshot("A"), screenshot("B")])
        let enumerator = SpyEnumerator()
        let env = makeEnv(index: index, enumerator: enumerator)

        // Ripristino deciso (indice non vuoto).
        XCTAssertEqual(LaunchRestoreCoordinator(environment: env).decision(), .restore)

        // Apertura di categoria (percorso on-tap della CategoryReviewView, cache-miss).
        let data = try CategoryReviewSource.reviewData(for: .screenshots, from: env)

        // Ha letto l'indice persistito (composizione dai dati veri)…
        XCTAssertGreaterThan(index.reads, 0, "l'apertura di categoria legge l'indice persistito")
        XCTAssertEqual(data.review.removableIds.count, 2, "i due screenshot seminati sono proposti")
        // …ma NON ha avviato una scansione unificata: nessuna ri-enumerazione, nessuna
        // riscrittura dell'indice.
        XCTAssertEqual(enumerator.calls, 0,
                       "aprire una categoria non ri-enumera la libreria (nessuna scansione unificata)")
        XCTAssertEqual(index.upsertCalls, 0, "aprire una categoria non riscrive l'indice")
        XCTAssertEqual(index.removeCalls, 0)
    }
}
