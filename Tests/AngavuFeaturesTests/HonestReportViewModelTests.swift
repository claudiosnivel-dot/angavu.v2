import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-114 — AC-114-1 / AC-114-2. Report onesto sui dati veri: spazio device mai
// promesso oltre il recuperabile reale; caveat iCloud derivato, mai dichiarato.

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

/// Residenza device configurabile: quota residente = `residentFraction` dei byte
/// libreria (per simulare originali in cloud quando optimize è attivo).
private struct FractionDeviceStorage: DeviceStorageInspecting {
    let optimize: ICloudOptimizeStorage
    let residentFraction: Double
    func optimizeStorageStatus() -> ICloudOptimizeStorage { optimize }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        Int64(Double(libraryBytes) * residentFraction)
    }
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

private func makeEnv(
    access: PhotoAccess,
    stored: [LibraryAsset],
    sizes: [String: ByteSize],
    optimize: ICloudOptimizeStorage,
    residentFraction: Double
) -> AppEnvironment {
    let index = FixedIndex(stored: stored)
    return AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: MapByteResolver(sizes: sizes),
        deviceStorage: FractionDeviceStorage(optimize: optimize, residentFraction: residentFraction)
    )
}

final class HonestReportViewModelTests: XCTestCase {

    // AC-114-1: byte device < byte libreria → deviceReclaimableNow < libraryFreed
    // e iCloudCaveat vero.
    func test_deviceLessThanLibraryYieldsCaveat() {
        let vm = HonestReportViewModel(environment: makeEnv(
            access: .full,
            stored: [photo("P1")],
            sizes: ["P1": .exact(bytes: 1000)],
            optimize: .enabled,
            residentFraction: 0.4
        ))

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.libraryReclaimable, 1000)
        XCTAssertEqual(screen.deviceReclaimableNow, 400)
        XCTAssertLessThan(screen.deviceReclaimableNow, screen.libraryReclaimable)
        XCTAssertTrue(screen.iCloudCaveat, "originali in cloud: il caveat va segnalato")
    }

    // AC-114-2: byte device pari ai byte libreria → iCloudCaveat falso.
    func test_deviceEqualsLibraryNoCaveat() {
        let vm = HonestReportViewModel(environment: makeEnv(
            access: .full,
            stored: [photo("P1")],
            sizes: ["P1": .exact(bytes: 1000)],
            optimize: .disabled,
            residentFraction: 1.0
        ))

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertEqual(screen.deviceReclaimableNow, screen.libraryReclaimable)
        XCTAssertFalse(screen.iCloudCaveat)
    }

    // Con accesso limited il report marca i conteggi parziali e invita all'accesso
    // completo (onestà dei numeri, riuso di HonestReport).
    func test_limitedAccessMarksPartialAndInvitesFullAccess() {
        let vm = HonestReportViewModel(environment: makeEnv(
            access: .limited,
            stored: [photo("P1")],
            sizes: ["P1": .exact(bytes: 10)],
            optimize: .disabled,
            residentFraction: 1.0
        ))

        guard case .ready(let screen) = vm.load() else { return XCTFail("atteso ready") }

        XCTAssertTrue(screen.report.countsArePartial)
        XCTAssertTrue(screen.report.invitesFullAccess)
    }
}
