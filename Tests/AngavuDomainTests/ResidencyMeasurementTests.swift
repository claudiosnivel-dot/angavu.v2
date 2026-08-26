import XCTest
@testable import AngavuDomain

// P0-2b — Oracolo di dominio della residenza per-asset reale.
//
// Verifica, senza device, le invarianti d'onestà: byte device mai > libreria; un
// originale non servibile offline conta 0; la misura è determinata SOLO a copertura
// piena; cancellazione/errore → indeterminata (residui non misurati, nessun numero
// fabbricato); una misura determinata pilota il numero device della dashboard.

final class ResidencyMeasurementTests: XCTestCase {

    // Probe fake: byte device per id; registra gli id realmente sondati. Può
    // cancellare il token dopo N sonde, per provare lo stop cooperativo a blocchi.
    private final class FakeProbe: AssetResidencyProbing {
        var deviceBytesByID: [String: Int64]
        private(set) var probedIDs: [String] = []
        var cancelAfter: Int?
        let token: CancellationToken

        init(
            _ deviceBytesByID: [String: Int64],
            token: CancellationToken = CancellationToken(),
            cancelAfter: Int? = nil
        ) {
            self.deviceBytesByID = deviceBytesByID
            self.token = token
            self.cancelAfter = cancelAfter
        }

        func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
            probedIDs.append(id)
            if let limit = cancelAfter, probedIDs.count >= limit { token.cancel() }
            return deviceBytesByID[id] ?? libraryBytes
        }
    }

    private func item(_ id: String, _ library: Int64) -> ResidencyProbeItem {
        ResidencyProbeItem(id: id, libraryBytes: library)
    }

    // Copertura piena → misura determinata con la somma dei byte device reali.
    func test_completedRun_isDeterminate_withMeasuredDeviceBytes() {
        let items = [item("a", 1_000), item("b", 8_000), item("c", 5_000)]
        let probe = FakeProbe(["a": 1_000, "b": 0, "c": 5_000]) // b è in cloud
        let outcome = ResidencyAggregator.measure(
            items: items, probe: probe, chunkSize: 2, cancellation: CancellationToken()
        )
        let measurement = ResidencyAggregator.measurement(from: outcome)

        XCTAssertTrue(measurement.isDeterminate)
        XCTAssertEqual(measurement.coveredCount, 3)
        XCTAssertEqual(measurement.totalCount, 3)
        XCTAssertEqual(measurement.deviceResidentBytes, 6_000) // 1000 + 0 + 5000
        XCTAssertEqual(measurement.libraryBytes, 14_000)
    }

    // Invariante d'onestà: un probe che sovrastima (device > libreria) viene ricondotto
    // al tetto per-asset; il totale non supera mai la libreria.
    func test_perAssetDeviceNeverExceedsLibrary() {
        let items = [item("a", 1_000)]
        let probe = FakeProbe(["a": 999_999])
        let measurement = ResidencyAggregator.measurement(
            from: ResidencyAggregator.measure(items: items, probe: probe, cancellation: CancellationToken())
        )
        XCTAssertEqual(measurement.deviceResidentBytes, 1_000)
        XCTAssertLessThanOrEqual(measurement.deviceResidentBytes, measurement.libraryBytes)
    }

    // Originale non servibile offline (probe = 0) → 0 byte device per quell'asset.
    func test_nonResidentAssetCountsZero() {
        let items = [item("cloud", 10_000)]
        let probe = FakeProbe(["cloud": 0])
        let measurement = ResidencyAggregator.measurement(
            from: ResidencyAggregator.measure(items: items, probe: probe, cancellation: CancellationToken())
        )
        XCTAssertEqual(measurement.deviceResidentBytes, 0)
        XCTAssertTrue(measurement.isDeterminate)
    }

    // Cancellazione fra i blocchi: i residui NON vengono sondati e la misura è
    // indeterminata — nessun numero device parziale spacciato per totale.
    func test_cancelledRun_isIndeterminate_leavesRemainderUnprobed() {
        let items = (0..<10).map { item("id\($0)", 1_000) }
        let token = CancellationToken()
        let probe = FakeProbe([:], token: token, cancelAfter: 2)
        let outcome = ResidencyAggregator.measure(
            items: items, probe: probe, chunkSize: 2, cancellation: token
        )
        let measurement = ResidencyAggregator.measurement(from: outcome)

        XCTAssertFalse(measurement.isDeterminate, "cancellata ⇒ non affidabile")
        XCTAssertEqual(measurement.deviceResidentBytes, 0, "nessun numero device parziale")
        XCTAssertLessThan(probe.probedIDs.count, items.count, "i residui non sono stati sondati")
    }

    // Esito failed → misura indeterminata (caveat), mai un numero. Il port non è
    // throwing; l'errore nel fold è modellato dal motore, qui si verifica il mapping.
    func test_failedRun_isIndeterminate() {
        let reached = AnalysisProgress(processed: 1, total: 4)
        let outcome: AnalysisOutcome<ResidencyMeasurement> = .failed(reason: AnalysisFailure("io"), at: reached)
        let measurement = ResidencyAggregator.measurement(from: outcome)
        XCTAssertFalse(measurement.isDeterminate)
        XCTAssertEqual(measurement.deviceResidentBytes, 0)
        XCTAssertEqual(measurement.totalCount, 4)
    }

    // Libreria vuota → determinata banalmente, 0 byte (nulla da misurare).
    func test_emptyLibrary_isDeterminateZero() {
        let measurement = ResidencyAggregator.measurement(
            from: ResidencyAggregator.measure(items: [], probe: FakeProbe([:]), cancellation: CancellationToken())
        )
        XCTAssertTrue(measurement.isDeterminate)
        XCTAssertEqual(measurement.deviceResidentBytes, 0)
        XCTAssertEqual(measurement.totalCount, 0)
    }

    // Integrazione col calcolo: misura determinata → la dashboard mostra il numero
    // device MISURATO (~8 GB del device di test), non l'euristica, col tetto di realtà.
    func test_determinateMeasurement_drivesReclaimableDeviceNumber() {
        let gb: Int64 = 1_000_000_000
        let items = [DeletedAssetSize(libraryBytes: 139 * gb, deviceResidentBytes: 139 * gb)]
        let measured = ResidencyMeasurement(
            deviceResidentBytes: 8 * gb, libraryBytes: 139 * gb, coveredCount: 1, totalCount: 1
        )
        let capacity = DeviceStorageCapacity(totalCapacityBytes: 128 * gb, availableBytes: 46 * gb)

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items,
            optimizeStorage: .enabled,
            deviceCapacity: capacity,
            residencyDeterminate: false, // l'euristica direbbe "caveat"…
            measuredResidency: measured  // …ma la misura reale vince.
        )

        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 8 * gb, "numero device reale, non 139")
        XCTAssertEqual(space.reclaimableLibrarySpace, 139 * gb)
        XCTAssertFalse(space.deviceSpaceIsIndeterminate, "misura completa ⇒ determinato")
        XCTAssertTrue(space.iCloudCaveat, "8 < 139 ⇒ gran parte è in iCloud, caveat sempre")
    }

    // Misura indeterminata → NON sovrascrive: resta il caveat P0-3 (nessun numero).
    func test_indeterminateMeasurement_fallsBackToCaveat() {
        let gb: Int64 = 1_000_000_000
        let items = [DeletedAssetSize(libraryBytes: 139 * gb, deviceResidentBytes: 139 * gb)]
        let partial = ResidencyMeasurement.indeterminate(coveredCount: 3, totalCount: 10)

        let space = ReclaimableSpaceCalculator.reclaimable(
            from: items,
            optimizeStorage: .enabled,
            residencyDeterminate: false,
            measuredResidency: partial
        )

        XCTAssertTrue(space.deviceSpaceIsIndeterminate, "misura parziale ⇒ ancora caveat")
        XCTAssertTrue(space.iCloudCaveat)
        XCTAssertEqual(space.reclaimableLibrarySpace, 139 * gb, "la libreria resta un numero vero")
    }
}
