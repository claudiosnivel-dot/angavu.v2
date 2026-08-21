import XCTest
@testable import AngavuDomain

// T-021 — AC-021-1 / AC-021-2. Caveat iCloud: spazio libreria vs device liberabile ora.

final class ICloudCaveatTests: XCTestCase {

    // AC-021-1: optimize-storage attivo e originali nel cloud → spazio device
    // liberabile ora INFERIORE allo spazio libreria e caveat segnalato.
    func test_optimizeStorageEnabled_deviceLessThanLibraryAndCaveat() {
        let items = [
            // Residente per intero.
            DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000),
            // Originale nel cloud: sul device quasi nulla.
            DeletedAssetSize(libraryBytes: 8_000, deviceResidentBytes: 300)
        ]

        let space = ReclaimableSpaceCalculator.reclaimable(from: items, optimizeStorage: .enabled)

        XCTAssertEqual(space.reclaimableLibrarySpace, 9_000)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 1_300)
        XCTAssertLessThan(space.reclaimableDeviceSpaceNow, space.reclaimableLibrarySpace)
        XCTAssertTrue(space.iCloudCaveat, "con originali nel cloud il caveat va segnalato")
    }

    // AC-021-2: optimize-storage non attivo → device liberabile ora COINCIDE con
    // lo spazio libreria (nessuna quota bloccata in cloud), nessun caveat.
    func test_optimizeStorageDisabled_deviceEqualsLibraryNoCaveat() {
        let items = [
            DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000),
            DeletedAssetSize(libraryBytes: 8_000, deviceResidentBytes: 8_000)
        ]

        let space = ReclaimableSpaceCalculator.reclaimable(from: items, optimizeStorage: .disabled)

        XCTAssertEqual(space.reclaimableLibrarySpace, 9_000)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 9_000)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, space.reclaimableLibrarySpace)
        XCTAssertFalse(space.iCloudCaveat, "senza optimize-storage non c'è caveat")
    }

    // Anche con byte residenti incoerenti in input, disabled forza device == libreria:
    // la coincidenza non dipende dai byte residenti per-asset.
    func test_disabledIgnoresPerAssetResidentBytes() {
        let items = [DeletedAssetSize(libraryBytes: 5_000, deviceResidentBytes: 10)]

        let space = ReclaimableSpaceCalculator.reclaimable(from: items, optimizeStorage: .disabled)

        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 5_000)
        XCTAssertFalse(space.iCloudCaveat)
    }
}
