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

private func makeEnv(access: PhotoAccess, raws: [RawEnumeratedAsset], index: RecordingIndex) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(raws: raws),
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: StubDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

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
