import XCTest
@testable import AngavuDomain

// P0-3 — Tetto di realtà + caveat di residenza indeterminata.
//
// Oracolo di dominio del difetto device-only "139,21 GB liberabili sul telefono
// ora" su un telefono da 128 GB (POST-DEVICE-UX-PLAN §1). Il numero device onesto
// non può MAI superare la libreria, lo spazio libero del device, o la capacità del
// device; e quando la residenza non è determinabile si mostra un caveat, non una
// cifra fabbricata (manifesto: numeri veri, mai gonfiati).

final class RealityCeilingTests: XCTestCase {

    // Byte "stile file" (10^9), coerenti col device di test dell'utente.
    private let gb: Int64 = 1_000_000_000

    // Invariante 1: device-now <= libreria (già garantito dal costruttore, ma
    // pinnato qui perché è il primo tetto del contratto).
    func test_deviceNow_neverExceedsLibrary() {
        // Residenza sovrastimata (uguale alla libreria) senza capacità nota: il
        // solo cap libreria tiene device == libreria, mai oltre.
        let items = [DeletedAssetSize(libraryBytes: 5_000, deviceResidentBytes: 999_999)]
        let space = ReclaimableSpaceCalculator.reclaimable(from: items, optimizeStorage: .enabled)
        XCTAssertLessThanOrEqual(space.reclaimableDeviceSpaceNow, space.reclaimableLibrarySpace)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 5_000)
    }

    // Invariante 2 e 3: device-now <= spazio libero e <= capacità del device.
    // Residenza sovrastimata (= libreria 139 GB) ma capacità reale del device:
    // il tetto la riporta entro min(libero, capacità).
    func test_deviceNow_cappedByFreeSpaceAndCapacity() {
        let library = 139 * gb
        let items = [DeletedAssetSize(libraryBytes: library, deviceResidentBytes: library)]
        let capacity = DeviceStorageCapacity(totalCapacityBytes: 128 * gb, availableBytes: 46 * gb)

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items, optimizeStorage: .enabled, deviceCapacity: capacity
        )

        // Mai oltre nessuno dei tre tetti.
        XCTAssertLessThanOrEqual(space.reclaimableDeviceSpaceNow, capacity.availableBytes)
        XCTAssertLessThanOrEqual(space.reclaimableDeviceSpaceNow, capacity.totalCapacityBytes)
        XCTAssertLessThanOrEqual(space.reclaimableDeviceSpaceNow, space.reclaimableLibrarySpace)
        // min(139, 46, 128) = 46 GB (tetto conservativo contro la sovrastima).
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 46 * gb)
        XCTAssertTrue(space.iCloudCaveat, "device < libreria ⇒ caveat")
    }

    // Il caso reale del device dell'utente: residenza CORRETTA ~8 GB, libreria 139 GB,
    // capacità 128 GB, libero 46 GB → mostra ~8 GB (non 139) + caveat. È l'esito che
    // il device-test pretendeva.
    func test_userDeviceCase_showsResidentNotLibrary() {
        let library = 139 * gb
        let resident = 8 * gb
        let items = [DeletedAssetSize(libraryBytes: library, deviceResidentBytes: resident)]
        let capacity = DeviceStorageCapacity(totalCapacityBytes: 128 * gb, availableBytes: 46 * gb)

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items, optimizeStorage: .enabled, deviceCapacity: capacity
        )

        // 8 <= 46 <= 128 <= 139 → il tetto non vincola: si mostra la residenza reale.
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, resident)
        XCTAssertEqual(space.reclaimableLibrarySpace, library)
        XCTAssertTrue(space.iCloudCaveat, "gran parte è in iCloud ⇒ caveat sempre")
        XCTAssertFalse(space.deviceSpaceIsIndeterminate)
    }

    // Tetto conservativo: se una grande quota fosse residente su un device quasi
    // pieno, il device-now è limitato dallo spazio libero (sotto-stima onesta, mai
    // gonfiata). Documenta il trade-off deciso con l'utente.
    func test_ceiling_isConservative_mayUnderReportButNeverInflates() {
        let items = [DeletedAssetSize(libraryBytes: 60 * gb, deviceResidentBytes: 60 * gb)]
        let capacity = DeviceStorageCapacity(totalCapacityBytes: 64 * gb, availableBytes: 5 * gb)

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items, optimizeStorage: .disabled, deviceCapacity: capacity
        )
        // min(60, 5, 64) = 5 GB: non gonfia oltre lo spazio fisicamente libero.
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 5 * gb)
    }

    // Residenza indeterminata: nessun numero device, solo caveat. Il valore grezzo
    // è azzerato e il flag lo dichiara non affidabile.
    func test_indeterminateResidency_yieldsCaveatNotNumber() {
        let items = [DeletedAssetSize(libraryBytes: 139 * gb, deviceResidentBytes: 139 * gb)]

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items, optimizeStorage: .enabled, residencyDeterminate: false
        )

        XCTAssertTrue(space.deviceSpaceIsIndeterminate)
        XCTAssertTrue(space.iCloudCaveat, "residenza indeterminata ⇒ caveat")
        XCTAssertEqual(space.reclaimableLibrarySpace, 139 * gb, "la libreria resta un numero vero")
    }

    // Senza capacità nota il comportamento storico è invariato (nessun tetto): la
    // firma retro-compatibile non cambia i verdi esistenti.
    func test_noCapacity_keepsHistoricBehavior() {
        let items = [
            DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000),
            DeletedAssetSize(libraryBytes: 8_000, deviceResidentBytes: 300)
        ]
        let space = ReclaimableSpaceCalculator.reclaimable(from: items, optimizeStorage: .enabled)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 1_300)
        XCTAssertFalse(space.deviceSpaceIsIndeterminate)
    }
}
