import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-112 — AC-112-1 / AC-112-2. Dashboard reale via view-model, con fake dietro i
// port dell'AppEnvironment. Nessun device: byte, accesso e residenza sono iniettati.

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

private struct ThrowingIndex: AssetIndexReading, AssetIndexWriting {
    struct BoomError: Error {}
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { throw BoomError() }
    func count() throws -> Int { 0 }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

/// Byte noti per id: prova che exact ed estimated restano separati (mai fusi).
private struct MapByteResolver: AssetByteSizeResolving {
    let sizes: [String: ByteSize]
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        sizes[localIdentifier] ?? .estimated(bytes: fallbackEstimate)
    }
}

private struct StubDeviceStorage: DeviceStorageInspecting {
    let optimize: ICloudOptimizeStorage
    func optimizeStorageStatus() -> ICloudOptimizeStorage { optimize }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

/// Come l'adapter reale (P0-2): la residenza è determinabile SOLO con optimize-storage
/// disattivo; con optimize attivo → indeterminata (caveat, non un numero).
private struct HonestStubDeviceStorage: DeviceStorageInspecting {
    let optimize: ICloudOptimizeStorage
    func optimizeStorageStatus() -> ICloudOptimizeStorage { optimize }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
    func residencyIsDeterminate() -> Bool { optimize == .disabled }
}

private struct FixedCapacity: DeviceCapacityReading {
    let capacity: DeviceStorageCapacity?
    func deviceCapacity() -> DeviceStorageCapacity? { capacity }
}

private func photo(_ id: String, screenshot: Bool = false) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .photo,
        pixelSize: PixelSize(width: 100, height: 100),
        creationDate: nil,
        subtypes: screenshot ? [.screenshot] : []
    )
}

private func video(_ id: String) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .video,
        pixelSize: PixelSize(width: 1920, height: 1080),
        creationDate: nil,
        subtypes: []
    )
}

private func makeEnv(
    access: PhotoAccess,
    index: any AssetIndexReading & AssetIndexWriting,
    sizes: [String: ByteSize],
    optimize: ICloudOptimizeStorage = .disabled,
    deviceStorage: (any DeviceStorageInspecting)? = nil,
    deviceCapacity: any DeviceCapacityReading = UnknownDeviceCapacity()
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(sizes: sizes),
        deviceStorage: deviceStorage ?? StubDeviceStorage(optimize: optimize),
        deviceCapacity: deviceCapacity,
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

final class DashboardScreenTests: XCTestCase {

    // AC-112-1: indice con foto e video e byte noti → righe per categoria coi byte
    // reali, exact ed estimated tenuti SEPARATI (mai fusi in un unico "esatto").
    func test_categoryRowsReportRealBytesExactSeparatedFromEstimated() async {
        let index = FixedIndex(stored: [photo("P1"), photo("P2"), video("V1"), video("V2")])
        let sizes: [String: ByteSize] = [
            "P1": .exact(bytes: 100),
            "P2": .estimated(bytes: 50),
            "V1": .exact(bytes: 1000),
            "V2": .estimated(bytes: 200)
        ]
        let vm = DashboardViewModel(environment: makeEnv(access: .full, index: index, sizes: sizes))

        guard case .ready(let screen) = await vm.load() else {
            return XCTFail("atteso stato ready")
        }

        let photoRow = screen.categories.first { $0.category == .photo }
        XCTAssertEqual(photoRow?.count, 2)
        XCTAssertEqual(photoRow?.exactBytes, 100)
        XCTAssertEqual(photoRow?.estimatedBytes, 50)
        XCTAssertEqual(photoRow?.hasEstimatedPortion, true, "la quota stimata non va nascosta")

        let videoRow = screen.categories.first { $0.category == .video }
        XCTAssertEqual(videoRow?.count, 2)
        XCTAssertEqual(videoRow?.exactBytes, 1000)
        XCTAssertEqual(videoRow?.estimatedBytes, 200)
    }

    // Le categorie sono disgiunte: uno screenshot conta come screenshot, non foto.
    func test_screenshotIsItsOwnCategory() async {
        let index = FixedIndex(stored: [photo("P1"), photo("S1", screenshot: true)])
        let sizes: [String: ByteSize] = [
            "P1": .exact(bytes: 10),
            "S1": .exact(bytes: 20)
        ]
        let vm = DashboardViewModel(environment: makeEnv(access: .full, index: index, sizes: sizes))

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.categories.first { $0.category == .photo }?.count, 1)
        XCTAssertEqual(screen.categories.first { $0.category == .screenshot }?.count, 1)
    }

    // AC-112-2: accesso limited → banner limited presente e totale marcato parziale.
    func test_limitedAccessShowsBannerAndMarksTotalPartial() async {
        let index = FixedIndex(stored: [photo("P1")])
        let vm = DashboardViewModel(
            environment: makeEnv(access: .limited, index: index, sizes: ["P1": .exact(bytes: 10)])
        )

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertTrue(screen.banner.showLimitedAccessBanner, "accesso limited: banner presente")
        XCTAssertTrue(screen.banner.isTotalPartial, "il totale limited è parziale")
        XCTAssertTrue(screen.isTotalPartial, "il modello di schermata espone il totale come parziale")
    }

    // Accesso pieno → nessun banner, totale non parziale (contro-prova AC-112-2).
    func test_fullAccessHasNoLimitedBannerAndTotalNotPartial() async {
        let index = FixedIndex(stored: [photo("P1")])
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: index, sizes: ["P1": .exact(bytes: 10)])
        )

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertFalse(screen.banner.showLimitedAccessBanner)
        XCTAssertFalse(screen.isTotalPartial)
    }

    // Spazio recuperabile: riuso di ReclaimableSpaceCalculator. Con optimize disabled
    // i byte device eguagliano quelli libreria → nessun caveat (coerenza col Domain).
    func test_reclaimableSpaceReusesCalculatorNoCaveatWhenOptimizeDisabled() async {
        let index = FixedIndex(stored: [photo("P1"), video("V1")])
        let sizes: [String: ByteSize] = ["P1": .exact(bytes: 100), "V1": .exact(bytes: 900)]
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: index, sizes: sizes, optimize: .disabled)
        )

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.reclaimable.reclaimableLibrarySpace, 1000)
        XCTAssertEqual(screen.reclaimable.reclaimableDeviceSpaceNow, 1000)
        XCTAssertFalse(screen.reclaimable.iCloudCaveat)
    }

    // P0-2 (wiring): optimize-storage attivo con l'adapter onesto → residenza
    // indeterminata propagata allo screen (la View mostra un caveat, non un numero).
    func test_optimizeEnabled_honestStorage_yieldsIndeterminateDeviceSpace() async {
        let index = FixedIndex(stored: [photo("P1"), video("V1")])
        let sizes: [String: ByteSize] = ["P1": .exact(bytes: 100), "V1": .exact(bytes: 900)]
        let vm = DashboardViewModel(
            environment: makeEnv(
                access: .full, index: index, sizes: sizes,
                deviceStorage: HonestStubDeviceStorage(optimize: .enabled)
            )
        )

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertTrue(screen.reclaimable.deviceSpaceIsIndeterminate, "optimize attivo ⇒ residenza indeterminata")
        XCTAssertTrue(screen.reclaimable.iCloudCaveat)
        XCTAssertEqual(screen.reclaimable.reclaimableLibrarySpace, 1000, "la libreria resta un numero vero")
    }

    // P0-2/P0-3 (wiring): il tetto di realtà (capacità/spazio libero) è cablato nel
    // reader → il device-now non supera lo spazio libero del device.
    func test_deviceCapacityCeiling_isWiredThroughReader() async {
        let index = FixedIndex(stored: [photo("P1"), video("V1")])
        let sizes: [String: ByteSize] = ["P1": .exact(bytes: 100), "V1": .exact(bytes: 900)]
        // Optimize disabled → device grezzo = libreria (1000), ma spazio libero = 300.
        let capacity = FixedCapacity(capacity: DeviceStorageCapacity(totalCapacityBytes: 5000, availableBytes: 300))
        let vm = DashboardViewModel(
            environment: makeEnv(
                access: .full, index: index, sizes: sizes, optimize: .disabled, deviceCapacity: capacity
            )
        )

        guard case .ready(let screen) = await vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.reclaimable.reclaimableDeviceSpaceNow, 300, "tetto di realtà: ≤ spazio libero")
        XCTAssertEqual(screen.reclaimable.reclaimableLibrarySpace, 1000)
    }

    // La lettura dell'indice può fallire: stato failed, mai un verde finto.
    func test_indexReadFailureYieldsFailedState() async {
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: ThrowingIndex(), sizes: [:])
        )
        if case .failed = await vm.load() {
            // atteso
        } else {
            XCTFail("atteso stato failed alla lettura dell'indice")
        }
    }
}
