import XCTest
@testable import AngavuDomain

// T-102 — AC-102-1 / AC-102-2. Il report onesto: numeri veri con caveat, mai un
// totale gonfiato né un conteggio parziale spacciato per totale.

final class HonestReportTests: XCTestCase {

    private func photo(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 100, height: 100),
                     creationDate: nil, subtypes: [])
    }

    // AC-102-1: aggregati con quota estimated e iCloud attivo → il report riporta
    // la stima come stima (nessun unico totale "esatto") e segnala il caveat iCloud.
    func test_estimatedAndICloudAreReportedHonestly() {
        let aggregate = DashboardAggregator.aggregate([
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 1_000)),
            SizedAsset(asset: photo("p2"), size: .estimated(bytes: 4_000))
        ])
        // iCloud "ottimizza spazio" attivo: parte dei byte non è residente sul device.
        let reclaimable = ReclaimableSpaceCalculator.reclaimable(
            from: [DeletedAssetSize(libraryBytes: 5_000, deviceResidentBytes: 1_000)],
            optimizeStorage: .enabled
        )

        let report = HonestReportComposer.compose(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: .full
        )

        XCTAssertTrue(report.hasEstimatedPortion, "c'è una porzione stimata")
        XCTAssertEqual(report.totalEstimatedBytes, 4_000, "la stima resta nella sua quota")
        XCTAssertNil(report.singleExactTotalBytes, "mai un unico totale 'esatto' con stima presente")
        XCTAssertTrue(report.iCloudCaveat, "il caveat iCloud va segnalato")
    }

    // Senza porzione stimata: un unico totale esatto è lecito ed è esposto.
    func test_exactOnlyExposesSingleExactTotal() {
        let aggregate = DashboardAggregator.aggregate([
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 2_000)),
            SizedAsset(asset: photo("p2"), size: .exact(bytes: 3_000))
        ])
        let reclaimable = ReclaimableSpaceCalculator.reclaimable(
            from: [DeletedAssetSize(libraryBytes: 5_000, deviceResidentBytes: 5_000)],
            optimizeStorage: .disabled
        )

        let report = HonestReportComposer.compose(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: .full
        )

        XCTAssertFalse(report.hasEstimatedPortion)
        XCTAssertEqual(report.singleExactTotalBytes, 5_000, "senza stima il totale esatto è presentabile")
        XCTAssertFalse(report.iCloudCaveat, "iCloud disattivo: device == libreria, nessun caveat")
    }

    // AC-102-2: accesso limited → i conteggi sono marcati parziali e si invita
    // all'accesso completo.
    func test_limitedAccessMarksPartialAndInvitesFullAccess() {
        let aggregate = DashboardAggregator.aggregate([
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 1_000))
        ])
        let reclaimable = ReclaimableSpaceCalculator.reclaimable(
            from: [DeletedAssetSize(libraryBytes: 1_000, deviceResidentBytes: 1_000)],
            optimizeStorage: .disabled
        )

        let report = HonestReportComposer.compose(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: .limited
        )

        XCTAssertTrue(report.countsArePartial, "con accesso limited il conteggio è parziale")
        XCTAssertTrue(report.invitesFullAccess, "si invita ad abilitare l'accesso completo")
    }

    // Con accesso full i conteggi non sono parziali e non si invita all'accesso.
    func test_fullAccessIsNotPartial() {
        let report = HonestReportComposer.compose(
            aggregate: DashboardAggregate(categories: []),
            reclaimable: ReclaimableSpace(reclaimableLibrarySpace: 0, reclaimableDeviceSpaceNow: 0),
            access: .full
        )
        XCTAssertFalse(report.countsArePartial)
        XCTAssertFalse(report.invitesFullAccess)
    }
}
