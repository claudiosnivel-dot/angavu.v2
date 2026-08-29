import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-J0 — Harness di verifica del cablaggio, LIVELLO A (CI attuale, nessuna nuova infra).
//
// Origine: `blueprint/WIRING-CENSUS.md` (2° device-test). Diversi adapter reali sono
// costruiti e testati in ISOLAMENTO, ma mai collegati nel grafo di produzione
// `AppEnvironment.live` — e la CI Apple non lo vedeva, perché testava la logica pura +
// l'adapter isolato, MAI la RADICE DI COMPOSIZIONE né il fatto che un ViewModel invochi
// davvero l'adapter iniettato. Questo file introduce le due convenzioni di Livello A che
// chiudono quel buco in CI, senza device:
//
//   (1) test della RADICE DI COMPOSIZIONE — costruisce `AppEnvironment.live(container:)`
//       su un `ModelContainer` in-memory e asserisce il TIPO CONCRETO dietro ogni port
//       (reale vs null-object). Se in FSE-J1 il deleter restasse il null-object
//       `NoAssetDeleter`, l'asserzione fallirebbe QUI, in CI (censimento C1: eliminazione
//       no-op perché nessun deleter è cablato in `AppEnvironment`).
//
//   (2) test del SEAM con SPIA — un adapter-spia (conforme a un port) registra le
//       invocazioni, per asserire che un ViewModel INVOCA DAVVERO l'adapter iniettato su
//       un'azione (non che "avrebbe potuto"). Becca un ViewModel che avanza solo lo stato
//       senza toccare l'adapter (censimento C1: `confirmDeletion()` fa solo avanzare il
//       gate → nessuna `delete(...)` sull'adapter).
//
// I task FSE-J1…J7 RIUSANO queste due convenzioni; qui vivono l'harness + un esempio verde
// per ciascuna, su port GIÀ cablati (radice: enumerator/indexReader/handleResolver; seam:
// il probe di residenza consultato da `DashboardViewModel.measureResidency`).

// MARK: - Livello A / convenzione 1 — radice di composizione

// `AppEnvironment.live` è Apple-only (SwiftData + Photos): l'harness della radice gira al
// confine Apple (`swift test` su macOS in CI). Su una piattaforma senza quei framework
// degrada a compilazione-fuori (mai un verde finto).
#if canImport(SwiftData) && canImport(Photos)
import SwiftData

/// Costruttore riusabile del grafo di PRODUZIONE su un contenitore in-memory (nessun
/// file, nessun device). Ogni test FSE-J che deve asserire il tipo concreto dietro un
/// port passa da qui.
@available(macOS 14, iOS 17, *)
enum LiveCompositionRoot {
    static func make() throws -> AppEnvironment {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AssetRecord.self, configurations: configuration)
        return AppEnvironment.live(container: container)
    }
}

@available(macOS 14, iOS 17, *)
final class CompositionRootWiringTests: XCTestCase {

    // AC-FSE-J0-1: nel grafo `live()`, i port cablati portano l'adapter REALE, non il
    // null-object. Esempio su tre port già cablati; i task FSE-J aggiungono i loro
    // (deleter, executor di sostituzione, store derivati, observer…).
    func test_liveGraph_wiresRealAdaptersNotNullObjects() throws {
        let env = try LiveCompositionRoot.make()

        // Enumeratore reale PhotoKit (non un placeholder).
        XCTAssertTrue(
            env.enumerator is SystemPhotoAssetEnumerator,
            "enumerator deve essere l'adapter PhotoKit reale nel grafo live()"
        )

        // Indice reale SwiftData (non un null-object).
        XCTAssertTrue(
            env.indexReader is SwiftDataAssetIndex,
            "indexReader deve essere l'indice SwiftData reale"
        )

        // Contrasto REALE vs NULL-OBJECT: il resolver batch reale sostituisce il default
        // null-object `EmptyAssetHandleResolver`. È ESATTAMENTE la forma d'asserzione che,
        // in FSE-J1, becca l'eliminazione lasciata sul null-object.
        XCTAssertTrue(
            env.handleResolver is PHAssetBatchResolver,
            "handleResolver deve essere l'adapter batch reale"
        )
        XCTAssertFalse(
            env.handleResolver is EmptyAssetHandleResolver,
            "handleResolver NON deve essere il null-object nel grafo live()"
        )
    }

    // AC-FSE-J1-2: nel grafo `live()`, il deleter è l'adapter REALE (allinea l'indice e
    // usa PhotoKit), NON il null-object `NoAssetDeleter`. Questa asserzione FALLIREBBE se
    // FSE-J1 avesse dimenticato di cablare il deleter — esattamente il bug del censimento
    // C1 (eliminazione no-op perché nessun deleter era in `AppEnvironment`).
    func test_liveGraph_wiresRealDeleterNotNullObject() throws {
        let env = try LiveCompositionRoot.make()
        XCTAssertTrue(
            env.assetDeleter is IndexAligningDeleter,
            "assetDeleter deve essere il deleter reale che allinea l'indice nel grafo live()"
        )
        XCTAssertFalse(
            env.assetDeleter is NoAssetDeleter,
            "assetDeleter NON deve essere il null-object nel grafo live() (censimento C1)"
        )
    }
}
#endif

// MARK: - Livello A / convenzione 2 — seam con spia (platform-puro, gira ovunque)

/// SPIA riusabile: registra ogni id sondato. Conforme a un port, così sta al posto
/// dell'adapter reale in un test del *seam*. La stessa forma — una classe che registra
/// le invocazioni — è ciò che FSE-J1 userà per provare che `confirmDeletion()` invoca
/// DAVVERO `delete(ids:)` sul deleter iniettato (e con ESATTAMENTE gli id selezionati).
private final class SpyResidencyProbe: AssetResidencyProbing {
    private(set) var probedIds: [String] = []
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        probedIds.append(id)
        return libraryBytes
    }
}

private struct SeamAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct SeamEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct SeamIndex: AssetIndexReading, AssetIndexWriting {
    let stored: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { stored }
    func count() throws -> Int { stored.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct SeamByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .exact(bytes: 100)
    }
}

/// Optimize-storage attivo + residenza NON determinata ⇒ per il numero device reale serve
/// una misura per-asset → `measureResidency` deve consultare il probe (il seam da provare).
private struct SeamDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .enabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
    func residencyIsDeterminate() -> Bool { false }
}

private func seamPhoto(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 100, height: 100), creationDate: nil, subtypes: [])
}

final class CompositionSeamSpyTests: XCTestCase {

    // AC-FSE-J0-1 (seam): il ViewModel INVOCA davvero l'adapter iniettato. Con una misura
    // richiesta (optimize on, residenza indeterminata), `measureResidency` consulta il probe
    // per OGNI asset dell'indice → la spia registra le invocazioni. Se il VM non toccasse
    // l'adapter (come `confirmDeletion()` no-op del censimento), `probedIds` resterebbe vuoto.
    func test_seam_viewModelInvokesInjectedAdapter() async {
        let index = SeamIndex(stored: [seamPhoto("P1"), seamPhoto("P2")])
        let spy = SpyResidencyProbe()
        let env = AppEnvironment(
            authorizer: SeamAuthorizer(),
            enumerator: SeamEnumerator(),
            indexReader: index,
            indexWriter: index,
            byteResolver: SeamByteResolver(),
            deviceStorage: SeamDeviceStorage(),
            residencyProbe: spy,
            videoExporter: NoopVideoExporter(),
            videoSpecProvider: NoopVideoSpecProvider()
        )
        let vm = DashboardViewModel(environment: env)

        _ = await vm.measureResidency()

        XCTAssertFalse(
            spy.probedIds.isEmpty,
            "il ViewModel deve INVOCARE il probe iniettato (se restasse vuoto, il seam è no-op)"
        )
        XCTAssertEqual(
            Set(spy.probedIds), ["P1", "P2"],
            "il probe è consultato con ESATTAMENTE gli id dell'indice (seam cablato)"
        )
    }
}
