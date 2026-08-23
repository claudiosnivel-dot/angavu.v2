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
    optimize: ICloudOptimizeStorage = .disabled
) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(sizes: sizes),
        deviceStorage: StubDeviceStorage(optimize: optimize)
    )
}

final class DashboardScreenTests: XCTestCase {

    // AC-112-1: indice con foto e video e byte noti → righe per categoria coi byte
    // reali, exact ed estimated tenuti SEPARATI (mai fusi in un unico "esatto").
    func test_categoryRowsReportRealBytesExactSeparatedFromEstimated() {
        let index = FixedIndex(stored: [photo("P1"), photo("P2"), video("V1"), video("V2")])
        let sizes: [String: ByteSize] = [
            "P1": .exact(bytes: 100),
            "P2": .estimated(bytes: 50),
            "V1": .exact(bytes: 1000),
            "V2": .estimated(bytes: 200)
        ]
        let vm = DashboardViewModel(environment: makeEnv(access: .full, index: index, sizes: sizes))

        guard case .ready(let screen) = vm.load() else {
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
    func test_screenshotIsItsOwnCategory() {
        let index = FixedIndex(stored: [photo("P1"), photo("S1", screenshot: true)])
        let sizes: [String: ByteSize] = [
            "P1": .exact(bytes: 10),
            "S1": .exact(bytes: 20)
        ]
        let vm = DashboardViewModel(environment: makeEnv(access: .full, index: index, sizes: sizes))

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.categories.first { $0.category == .photo }?.count, 1)
        XCTAssertEqual(screen.categories.first { $0.category == .screenshot }?.count, 1)
    }

    // AC-112-2: accesso limited → banner limited presente e totale marcato parziale.
    func test_limitedAccessShowsBannerAndMarksTotalPartial() {
        let index = FixedIndex(stored: [photo("P1")])
        let vm = DashboardViewModel(
            environment: makeEnv(access: .limited, index: index, sizes: ["P1": .exact(bytes: 10)])
        )

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertTrue(screen.banner.showLimitedAccessBanner, "accesso limited: banner presente")
        XCTAssertTrue(screen.banner.isTotalPartial, "il totale limited è parziale")
        XCTAssertTrue(screen.isTotalPartial, "il modello di schermata espone il totale come parziale")
    }

    // Accesso pieno → nessun banner, totale non parziale (contro-prova AC-112-2).
    func test_fullAccessHasNoLimitedBannerAndTotalNotPartial() {
        let index = FixedIndex(stored: [photo("P1")])
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: index, sizes: ["P1": .exact(bytes: 10)])
        )

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertFalse(screen.banner.showLimitedAccessBanner)
        XCTAssertFalse(screen.isTotalPartial)
    }

    // Spazio recuperabile: riuso di ReclaimableSpaceCalculator. Con optimize disabled
    // i byte device eguagliano quelli libreria → nessun caveat (coerenza col Domain).
    func test_reclaimableSpaceReusesCalculatorNoCaveatWhenOptimizeDisabled() {
        let index = FixedIndex(stored: [photo("P1"), video("V1")])
        let sizes: [String: ByteSize] = ["P1": .exact(bytes: 100), "V1": .exact(bytes: 900)]
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: index, sizes: sizes, optimize: .disabled)
        )

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.reclaimable.reclaimableLibrarySpace, 1000)
        XCTAssertEqual(screen.reclaimable.reclaimableDeviceSpaceNow, 1000)
        XCTAssertFalse(screen.reclaimable.iCloudCaveat)
    }

    // La lettura dell'indice può fallire: stato failed, mai un verde finto.
    func test_indexReadFailureYieldsFailedState() {
        let vm = DashboardViewModel(
            environment: makeEnv(access: .full, index: ThrowingIndex(), sizes: [:])
        )
        if case .failed = vm.load() {
            // atteso
        } else {
            XCTFail("atteso stato failed alla lettura dell'indice")
        }
    }
}
