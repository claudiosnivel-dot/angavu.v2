import XCTest
@testable import AngavuDomain

// T-052 — AC-052-1 / AC-052-2. Riepilogo post-eliminazione onesto e caveat iCloud.

final class DeletionSummaryTests: XCTestCase {

    // AC-052-1: 3 asset, iCloud non attivo (byte device == byte libreria) →
    // count 3 e libraryBytesFreed == deviceBytesReclaimableNow, nessun caveat.
    func test_noICloud_deviceEqualsLibrary() {
        let items = [
            DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000),
            DeletedAssetSize(libraryBytes: 2_000, deviceResidentBytes: 2_000),
            DeletedAssetSize(libraryBytes: 3_000, deviceResidentBytes: 3_000)
        ]

        let summary = DeletionSummaryComposer.compose(items)

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.libraryBytesFreed, 6_000)
        XCTAssertEqual(summary.deviceBytesReclaimableNow, 6_000)
        XCTAssertEqual(summary.deviceBytesReclaimableNow, summary.libraryBytesFreed)
        XCTAssertFalse(summary.iCloudCaveat, "senza iCloud optimize non c'è caveat")
    }

    // AC-052-2: iCloud optimize-storage attivo (alcuni originali nel cloud) →
    // deviceBytesReclaimableNow < libraryBytesFreed e caveat segnalato.
    func test_iCloudOptimize_deviceLessThanLibraryAndCaveatFlagged() {
        let items = [
            // Residente per intero.
            DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000),
            // Originale nel cloud: sul device solo una miniatura.
            DeletedAssetSize(libraryBytes: 5_000, deviceResidentBytes: 200)
        ]

        let summary = DeletionSummaryComposer.compose(items)

        XCTAssertEqual(summary.libraryBytesFreed, 6_000)
        XCTAssertEqual(summary.deviceBytesReclaimableNow, 1_200)
        XCTAssertLessThan(summary.deviceBytesReclaimableNow, summary.libraryBytesFreed)
        XCTAssertTrue(summary.iCloudCaveat, "spazio device non liberato ora deve segnalare il caveat")
    }

    // Invariante di onestà: byte device non superano mai i byte libreria, anche
    // con input incoerenti.
    func test_deviceBytesClampedToLibrary() {
        let item = DeletedAssetSize(libraryBytes: 100, deviceResidentBytes: 999)
        XCTAssertEqual(item.deviceResidentBytes, 100)

        let summary = DeletionSummaryComposer.compose([item])
        XCTAssertEqual(summary.deviceBytesReclaimableNow, 100)
        XCTAssertFalse(summary.iCloudCaveat)
    }
}
