import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// P0-2b (wiring) — Il probe di residenza per-asset è cablato nella dashboard: una
// misura reale e completa porta il numero device onesto (~8 GB del device di test)
// al posto del caveat; una misura cancellata/incompleta resta indeterminata (caveat).
// Nessun device: il probe è un fake che risponde per id. L'aggregazione è pura.

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    let access: PhotoAccess
    func currentAccess() -> PhotoAccess { access }
    func requestAccess() async -> PhotoAccess { access }
}

private struct StubEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct FixedIndex: AssetIndexReading, AssetIndexWriting {
    let stored: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { stored }
    func count() throws -> Int { stored.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct MapByteResolver: AssetByteSizeResolving {
    let sizes: [String: ByteSize]
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        sizes[localIdentifier] ?? .estimated(bytes: fallbackEstimate)
    }
}

/// Come l'adapter reale P0-2: senza misura per-asset la residenza è indeterminata
/// con optimize-storage attivo → caveat (non un numero).
private struct HonestStubDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .enabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
    func residencyIsDeterminate() -> Bool { false }
}

/// Probe fake: byte device per id. Un id assente conta 0 (originale in cloud). Può
/// cancellare il token dopo N sonde, per provare che una misura incompleta resta caveat.
private final class FakeResidencyProbe: AssetResidencyProbing {
    let deviceBytesByID: [String: Int64]
    let token: CancellationToken?
    let cancelAfter: Int?
    private(set) var probedCount = 0

    init(_ deviceBytesByID: [String: Int64], token: CancellationToken? = nil, cancelAfter: Int? = nil) {
        self.deviceBytesByID = deviceBytesByID
        self.token = token
        self.cancelAfter = cancelAfter
    }

    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        probedCount += 1
        if let limit = cancelAfter, probedCount >= limit { token?.cancel() }
        return deviceBytesByID[id] ?? 0
    }
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 100, height: 100), creationDate: nil, subtypes: [])
}

private func video(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .video, pixelSize: PixelSize(width: 1920, height: 1080), creationDate: nil, subtypes: [])
}

private func makeEnv(
    index: any AssetIndexReading & AssetIndexWriting,
    sizes: [String: ByteSize],
    probe: any AssetResidencyProbing
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: .full),
        enumerator: StubEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(sizes: sizes),
        deviceStorage: HonestStubDeviceStorage(),
        residencyProbe: probe,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

final class ResidencyWiringTests: XCTestCase {

    // Prima della misura: optimize attivo, residenza indeterminata → caveat, nessun numero.
    // Dopo `measureResidency`: misura completa → device-now = somma misurata (P1 residente,
    // V1 in cloud) e determinato.
    func test_measureResidency_replacesCaveatWithMeasuredDeviceNumber() async {
        let index = FixedIndex(stored: [photo("P1"), video("V1")])
        let sizes: [String: ByteSize] = ["P1": .exact(bytes: 100), "V1": .exact(bytes: 900)]
        let probe = FakeResidencyProbe(["P1": 100]) // V1 assente ⇒ 0 (in cloud)
        let vm = DashboardViewModel(environment: makeEnv(index: index, sizes: sizes, probe: probe))

        // Baseline: caveat.
        guard case .ready(let before) = await vm.load() else { return XCTFail("atteso ready") }
        XCTAssertTrue(before.reclaimable.deviceSpaceIsIndeterminate, "senza misura ⇒ caveat")

        // Dopo la misura: numero device reale.
        guard case .ready(let after) = await vm.measureResidency() else { return XCTFail("atteso ready") }
        XCTAssertFalse(after.reclaimable.deviceSpaceIsIndeterminate, "misura completa ⇒ determinato")
        XCTAssertEqual(after.reclaimable.reclaimableDeviceSpaceNow, 100, "solo P1 è residente")
        XCTAssertEqual(after.reclaimable.reclaimableLibrarySpace, 1000, "la libreria resta vera")
        XCTAssertTrue(after.reclaimable.iCloudCaveat, "100 < 1000 ⇒ gran parte in iCloud")
    }

    // Misura cancellata a metà → residui non misurati → resta indeterminata (caveat),
    // mai un numero device parziale.
    func test_cancelledMeasurement_staysCaveat() async {
        let index = FixedIndex(stored: (0..<20).map { photo("P\($0)") })
        var sizes: [String: ByteSize] = [:]
        for i in 0..<20 { sizes["P\(i)"] = .exact(bytes: 100) }
        let token = CancellationToken()
        let probe = FakeResidencyProbe(sizes.mapValues { _ in Int64(100) }, token: token, cancelAfter: 3)
        let vm = DashboardViewModel(environment: makeEnv(index: index, sizes: sizes, probe: probe))

        guard case .ready(let screen) = await vm.measureResidency(cancellation: token) else {
            return XCTFail("atteso ready")
        }
        XCTAssertTrue(screen.reclaimable.deviceSpaceIsIndeterminate, "misura incompleta ⇒ ancora caveat")
        XCTAssertLessThan(probe.probedCount, 20, "i residui non sono stati sondati")
        XCTAssertEqual(screen.reclaimable.reclaimableLibrarySpace, 2000, "la libreria resta vera")
    }
}
