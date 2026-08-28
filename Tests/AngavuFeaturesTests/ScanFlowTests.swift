import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-111 — AC-111-1 / AC-111-2. Flusso di scansione via view-model, con fake.

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

/// Come l'adapter reale con optimize-storage ATTIVO: la residenza per-asset non è
/// determinabile a buon mercato → la dashboard mostra il CAVEAT finché una misura
/// reale e completa (passo differito FSE-G1) non arriva.
private struct OptimizeOnDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .enabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
    func residencyIsDeterminate() -> Bool { false }
}

/// Probe di residenza che REGISTRA quante volte è stato sondato: sotto la strategia B
/// la scansione NON deve sondare la residenza (è differita), quindi `probedCount` resta 0.
private final class RecordingResidencyProbe: AssetResidencyProbing {
    private(set) var probedCount = 0
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        probedCount += 1
        return libraryBytes / 2
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
    residencyProbe: any AssetResidencyProbing = AssumeResidentResidencyProbe(),
    deviceStorage: any DeviceStorageInspecting = StubDeviceStorage()
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(raws: raws),
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: deviceStorage,
        residencyProbe: residencyProbe,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

// Byte libreria attesi per un `photo(_:)` di 100×100: la stima di ripiego è
// area * 2 = 10000 * 2 = 20000 (lo StubByteResolver marca `.estimated`).
private let expectedLibraryBytesPerPhoto: Int64 = 20000

final class ScanFlowTests: XCTestCase {

    // AC-111-1: authorizer=limited + 3 asset → indice con 3, stato parziale.
    func test_completesAndMarksPartialWhenLimited() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .limited, raws: [photo("A"), photo("B"), photo("C")], index: index)
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())

        XCTAssertEqual(final, .completed(indexed: 3, partialCount: true))
        XCTAssertEqual(index.upserted.map(\.id), ["A", "B", "C"])
    }

    // Accesso pieno → completato senza marca parziale.
    func test_fullAccessIsNotPartial() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A")], index: index)
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())
        XCTAssertEqual(final, .completed(indexed: 1, partialCount: false))
    }

    // AC-111-2: cancellazione → stato cancelled e NIENTE indicizzazione.
    // (La cancellazione a metà-blocco è coperta da LibraryAssetMappingTests; qui
    // si verifica che il view-model la propaghi e non scriva l'indice.)
    func test_cancelledDoesNotIndex() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A"), photo("B"), photo("C")], index: index)
        let vm = ScanViewModel(environment: env)

        let token = CancellationToken()
        token.cancel()
        let final = await vm.run(cancellation: token)

        if case .cancelled = final {
            XCTAssertTrue(index.upserted.isEmpty, "una scansione cancellata non deve indicizzare")
        } else {
            XCTFail("atteso stato cancelled, ottenuto \(final)")
        }
    }

    // Scansione UNIFICATA: a esito completo i numeri veri sono GIÀ calcolati e
    // esposti (`figures`), pronti da cachare → la dashboard non deve ricalcolare
    // (niente seconda attesa «Calcolo dei numeri veri…»).
    func test_completedComputesFiguresReadyForDashboard() async throws {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A"), photo("B"), photo("C")], index: index)
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())

        XCTAssertEqual(final, .completed(indexed: 3, partialCount: false))
        let figures = try XCTUnwrap(vm.figures)
        // Una categoria foto coi 3 elementi, byte reali aggregati.
        XCTAssertEqual(figures.categories.count, 1)
        XCTAssertEqual(figures.categories.first?.category, .photo)
        XCTAssertEqual(figures.categories.first?.count, 3)
        XCTAssertEqual(figures.reclaimable.reclaimableLibrarySpace, 3 * expectedLibraryBytesPerPhoto)
    }

    // FSE-G1 (strategia B) — la residenza device è DIFFERITA, fuori dal percorso
    // obbligatorio: con optimize-storage attivo la scansione atterra col CAVEAT (numeri
    // di libreria pronti, cifra device rimandata) e NON sonda la residenza. Il numero
    // device reale arriva DOPO, dal passo differito (coperto da `ResidencyWiringTests`).
    func test_deferredResidency_scanLandsWithCaveatAndDoesNotProbe() async throws {
        let index = RecordingIndex()
        let probe = RecordingResidencyProbe()
        let env = makeEnv(
            access: .full,
            raws: [photo("A"), photo("B")],
            index: index,
            residencyProbe: probe,
            deviceStorage: OptimizeOnDeviceStorage()
        )
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())
        XCTAssertEqual(final, .completed(indexed: 2, partialCount: false),
                       "la scansione si completa senza attendere la residenza (AC-FSE-G1-3)")

        let figures = try XCTUnwrap(vm.figures)
        let library = 2 * expectedLibraryBytesPerPhoto
        XCTAssertEqual(figures.reclaimable.reclaimableLibrarySpace, library, "i numeri di libreria ci sono già")
        XCTAssertTrue(figures.reclaimable.deviceSpaceIsIndeterminate,
                      "atterraggio B: caveat device, mai un numero fabbricato prima della misura")
        XCTAssertEqual(probe.probedCount, 0, "la scansione non sonda la residenza: è differita")
    }

    // Una scansione cancellata non lascia numeri veri da cachare: la dashboard, se
    // aperta, ricalcolerà (nessun numero stantìo o parziale spacciato per fresco).
    func test_cancelledLeavesNoFigures() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A"), photo("B"), photo("C")], index: index)
        let vm = ScanViewModel(environment: env)

        let token = CancellationToken()
        token.cancel()
        _ = await vm.run(cancellation: token)

        XCTAssertNil(vm.figures)
    }

    // Accesso negato → failed, nessuna enumerazione indicizzata.
    func test_deniedFails() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .denied, raws: [photo("A")], index: index)
        let vm = ScanViewModel(environment: env)

        let final = await vm.run(cancellation: CancellationToken())
        if case .failed = final {
            XCTAssertTrue(index.upserted.isEmpty)
        } else {
            XCTFail("atteso stato failed, ottenuto \(final)")
        }
    }
}
