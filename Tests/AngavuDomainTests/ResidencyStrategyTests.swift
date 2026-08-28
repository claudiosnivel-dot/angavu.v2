import XCTest
import AngavuDomain

// Oracolo di FSE-G1 — policy PURA della residenza device (strategia B: residenza
// fuori dal percorso obbligatorio). Prova l'invariante di onestà ASSOLUTO (un numero
// device solo da misura reale e completa; ogni misura incompleta → caveat) e che la
// strategia `deferred` sblocca la completezza della scansione senza la residenza.

final class ResidencyStrategyTests: XCTestCase {

    // Item libreria per il calcolo: N asset da `libraryBytes` ciascuno.
    private func items(count: Int, libraryBytes: Int64) -> [DeletedAssetSize] {
        (0..<count).map { _ in
            DeletedAssetSize(libraryBytes: libraryBytes, deviceResidentBytes: libraryBytes)
        }
    }

    // MARK: AC-FSE-G1-1 — misura incompleta ⇒ CAVEAT, mai un numero device.

    // Misura CANCELLATA (residui non misurati): la policy mostra il caveat, coerente
    // con ReclaimableSpace/P0-3, indipendentemente dallo stato optimize-storage.
    func test_incompleteMeasurement_cancelled_yieldsCaveat() {
        let cancelled = ResidencyMeasurement.indeterminate(coveredCount: 3, totalCount: 10)
        XCTAssertFalse(cancelled.isDeterminate)

        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: cancelled,
            from: items(count: 10, libraryBytes: 100),
            optimizeStorage: .enabled,
            residencyDeterminate: false
        )

        XCTAssertTrue(space.deviceSpaceIsIndeterminate, "misura incompleta ⇒ caveat")
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 0, "nessun numero device parziale")
        XCTAssertEqual(space.reclaimableLibrarySpace, 1000, "la libreria resta vera")
        XCTAssertTrue(space.iCloudCaveat)
    }

    // Misura a CAMPIONE (copertura parziale per decidere se vale la misura piena):
    // NON è un numero device — resta il caveat (security_notes FSE-G1). Vale anche se
    // per assurdo l'ambiente si dichiarasse determinato: una misura tentata e incompleta
    // forza il caveat.
    func test_incompleteMeasurement_sample_yieldsCaveat_evenIfEnvironmentDeterminate() {
        // Campione: coperti 2 su 100, con byte device non nulli — comunque incompleto.
        let sample = ResidencyMeasurement(
            deviceResidentBytes: 50, libraryBytes: 200, coveredCount: 2, totalCount: 100
        )
        XCTAssertFalse(sample.isDeterminate)

        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: sample,
            from: items(count: 100, libraryBytes: 100),
            optimizeStorage: .disabled,
            residencyDeterminate: true // ambiente "determinato": ignorato, misura incompleta
        )

        XCTAssertTrue(space.deviceSpaceIsIndeterminate, "campione ⇒ mai un numero device")
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 0)
    }

    // MARK: AC-FSE-G1-2 — misura reale e completa ⇒ numero device col tetto di realtà.

    // Copertura piena: la policy restituisce il numero device MISURATO (non l'euristica
    // optimize-storage), col tetto di realtà P0-2b/P0-3 (min con capacità/spazio libero).
    func test_completeMeasurement_yieldsMeasuredDeviceNumberWithRealityCap() {
        // 10 asset da 100 = 1000 libreria; device misurato 600 (parte in cloud).
        let complete = ResidencyMeasurement(
            deviceResidentBytes: 600, libraryBytes: 1000, coveredCount: 10, totalCount: 10
        )
        XCTAssertTrue(complete.isDeterminate)

        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: complete,
            from: items(count: 10, libraryBytes: 100),
            optimizeStorage: .enabled,
            deviceCapacity: nil,
            residencyDeterminate: false
        )

        XCTAssertTrue(space.deviceSpaceIsDeterminate, "misura completa ⇒ numero reale, non caveat")
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 600, "il device è la somma MISURATA")
        XCTAssertEqual(space.reclaimableLibrarySpace, 1000)
        XCTAssertTrue(space.iCloudCaveat, "600 < 1000 ⇒ parte in iCloud, caveat comunque segnalato")
    }

    // Il tetto di realtà (P0-3) vincola il device-now allo spazio libero/capacità del
    // device quando nota: un device quasi pieno non promette più di quanto ha libero.
    func test_completeMeasurement_isCappedToDeviceFreeSpace() {
        let complete = ResidencyMeasurement(
            deviceResidentBytes: 900, libraryBytes: 1000, coveredCount: 10, totalCount: 10
        )
        let capacity = DeviceStorageCapacity(totalCapacityBytes: 2000, availableBytes: 300)

        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: complete,
            from: items(count: 10, libraryBytes: 100),
            optimizeStorage: .enabled,
            deviceCapacity: capacity,
            residencyDeterminate: false
        )

        XCTAssertTrue(space.deviceSpaceIsDeterminate)
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 300, "tetto = spazio libero del device")
    }

    // MARK: AC-FSE-G1-3 — deferred ⇒ la scansione può completarsi senza la residenza.

    // La strategia `deferred` NON blocca la completezza della scansione: indice + numeri
    // categoria pronti ⇒ scansione `completed`, la residenza si completa dopo.
    func test_deferredStrategy_doesNotBlockScanCompletion() {
        XCTAssertFalse(ResidencyPolicy.blocksScanCompletion(.deferred))
        XCTAssertTrue(
            ResidencyPolicy.decide(strategy: .deferred, measurement: nil).scanMayCompleteWithoutResidency,
            "deferred: la scansione può chiudersi senza aver misurato la residenza"
        )
        // Anche con una misura incompleta a bordo, deferred resta non-bloccante.
        let incomplete = ResidencyMeasurement.indeterminate(coveredCount: 1, totalCount: 5)
        XCTAssertTrue(
            ResidencyPolicy.decide(strategy: .deferred, measurement: incomplete).scanMayCompleteWithoutResidency
        )
    }

    // La strategia `blocking` (comportamento #78) mantiene la residenza sul percorso:
    // la scansione la richiede per dirsi completa. Speculare a `deferred`.
    func test_blockingStrategy_requiresResidencyOnScanPath() {
        XCTAssertTrue(ResidencyPolicy.blocksScanCompletion(.blocking))
        XCTAssertFalse(
            ResidencyPolicy.decide(strategy: .blocking, measurement: nil).scanMayCompleteWithoutResidency
        )
    }

    // MARK: Invarianti di `decide` — la misura è usabile SSE reale e completa.

    func test_decide_usesMeasurementOnlyWhenComplete() {
        let complete = ResidencyMeasurement(
            deviceResidentBytes: 10, libraryBytes: 20, coveredCount: 4, totalCount: 4
        )
        let incomplete = ResidencyMeasurement.indeterminate(coveredCount: 2, totalCount: 4)

        XCTAssertEqual(ResidencyPolicy.decide(strategy: .deferred, measurement: complete).measuredResidency,
                       complete, "completa ⇒ usabile")
        XCTAssertNil(ResidencyPolicy.decide(strategy: .deferred, measurement: incomplete).measuredResidency,
                     "incompleta ⇒ non usabile (caveat a valle)")
        XCTAssertNil(ResidencyPolicy.decide(strategy: .deferred, measurement: nil).measuredResidency,
                     "assente ⇒ non usabile")
        XCTAssertFalse(ResidencyPolicy.decide(strategy: .deferred, measurement: incomplete).showsMeasuredDeviceSpace)
        XCTAssertTrue(ResidencyPolicy.decide(strategy: .deferred, measurement: complete).showsMeasuredDeviceSpace)
    }

    // Misura ASSENTE + optimize DISATTIVO: non serve alcun probe: ogni originale è
    // residente ⇒ device == libreria, numero onesto senza caveat (nessuna attesa
    // differita necessaria). La policy rispetta la determinabilità dell'ambiente.
    func test_absentMeasurement_optimizeDisabled_yieldsDeviceEqualsLibrary() {
        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: nil,
            from: items(count: 5, libraryBytes: 100),
            optimizeStorage: .disabled,
            residencyDeterminate: true
        )
        XCTAssertTrue(space.deviceSpaceIsDeterminate, "optimize off ⇒ residenza nota, nessun caveat")
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 500, "device == libreria")
        XCTAssertEqual(space.reclaimableLibrarySpace, 500)
        XCTAssertFalse(space.iCloudCaveat)
    }

    // Misura ASSENTE + optimize ATTIVO: è l'atterraggio della strategia B — caveat,
    // finché il passo differito non porta la misura reale. Nessun numero fabbricato.
    func test_absentMeasurement_optimizeEnabled_yieldsCaveat_theDeferredLanding() {
        let space = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: nil,
            from: items(count: 5, libraryBytes: 100),
            optimizeStorage: .enabled,
            residencyDeterminate: false
        )
        XCTAssertTrue(space.deviceSpaceIsIndeterminate, "atterraggio B: caveat prima della misura")
        XCTAssertEqual(space.reclaimableDeviceSpaceNow, 0)
        XCTAssertEqual(space.reclaimableLibrarySpace, 500, "i numeri di libreria ci sono già")
    }
}
