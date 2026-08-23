import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — Dashboard: la presentazione PURA dello stato dashboard è l'oracolo
// della logica di schermata (quali righe, quali numeri, quale onestà). La resa
// SwiftUI resta compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class DashboardPresentationTests: XCTestCase {

    // Helpers per costruire uno `DashboardScreen` senza device.
    private func screen(
        categories: [CategoryBytes],
        reclaimable: ReclaimableSpace = ReclaimableSpace(reclaimableLibrarySpace: 0, reclaimableDeviceSpaceNow: 0),
        banner: DashboardBanner = DashboardBanner(showLimitedAccessBanner: false, isTotalPartial: false)
    ) -> DashboardScreen {
        DashboardScreen(categories: categories, reclaimable: reclaimable, banner: banner)
    }

    // idle → schermata di caricamento, nessuna riga, nessun errore.
    func test_idle_isLoadingWithNoRows() {
        let pres = DashboardPresentation(state: .idle)
        XCTAssertEqual(pres.kind, .idle)
        XCTAssertTrue(pres.categoryRows.isEmpty)
        XCTAssertNil(pres.reclaimable)
        XCTAssertFalse(pres.showsRetry)
        XCTAssertNotNil(pres.detail)
    }

    // ready → una riga per categoria, in ordine stabile, coi titoli localizzati.
    func test_ready_mapsCategoriesToLocalizedRows() {
        let categories = [
            CategoryBytes(category: .photo, count: 3, exactBytes: 300, estimatedBytes: 0),
            CategoryBytes(category: .video, count: 1, exactBytes: 900, estimatedBytes: 0),
            CategoryBytes(category: .screenshot, count: 2, exactBytes: 40, estimatedBytes: 0)
        ]
        let pres = DashboardPresentation(state: .ready(screen(categories: categories)))

        XCTAssertEqual(pres.kind, .ready)
        XCTAssertEqual(pres.categoryRows.map(\.category), [.photo, .video, .screenshot])
        XCTAssertEqual(pres.categoryRows.map(\.title), ["Foto", "Video", "Screenshot"])
        XCTAssertEqual(pres.categoryRows.first { $0.category == .photo }?.count, 3)
    }

    // Onestà: una quota stimata è SEMPRE marcata; una categoria tutta-exact no.
    func test_ready_marksEstimatedPortionNeverPassedAsExact() {
        let categories = [
            CategoryBytes(category: .photo, count: 2, exactBytes: 100, estimatedBytes: 50),
            CategoryBytes(category: .video, count: 1, exactBytes: 1000, estimatedBytes: 0)
        ]
        let pres = DashboardPresentation(state: .ready(screen(categories: categories)))

        let photoRow = pres.categoryRows.first { $0.category == .photo }
        XCTAssertEqual(photoRow?.isEstimated, true, "la quota stimata non va nascosta")
        XCTAssertEqual(photoRow?.totalBytes, 150)

        let videoRow = pres.categoryRows.first { $0.category == .video }
        XCTAssertEqual(videoRow?.isEstimated, false, "una categoria interamente esatta non è marcata")
    }

    // Spazio recuperabile: device < libreria → caveat iCloud esposto.
    func test_ready_surfacesICloudCaveatWhenDeviceFreesLessThanLibrary() {
        let reclaimable = ReclaimableSpace(reclaimableLibrarySpace: 1000, reclaimableDeviceSpaceNow: 400)
        let pres = DashboardPresentation(state: .ready(screen(categories: [], reclaimable: reclaimable)))

        XCTAssertEqual(pres.reclaimable?.libraryBytes, 1000)
        XCTAssertEqual(pres.reclaimable?.deviceBytesNow, 400)
        XCTAssertEqual(pres.reclaimable?.iCloudCaveat, true, "il caveat iCloud non va nascosto")
    }

    // Device == libreria → nessun caveat (contro-prova).
    func test_ready_noICloudCaveatWhenDeviceFreesAll() {
        let reclaimable = ReclaimableSpace(reclaimableLibrarySpace: 1000, reclaimableDeviceSpaceNow: 1000)
        let pres = DashboardPresentation(state: .ready(screen(categories: [], reclaimable: reclaimable)))

        XCTAssertEqual(pres.reclaimable?.iCloudCaveat, false)
    }

    // Accesso limited → banner presente e totale dichiarato PARZIALE, mai totale.
    func test_ready_limitedAccessShowsBannerAndMarksPartial() {
        let banner = DashboardBanner(showLimitedAccessBanner: true, isTotalPartial: true)
        let pres = DashboardPresentation(state: .ready(screen(categories: [], banner: banner)))

        XCTAssertTrue(pres.showsLimitedBanner)
        XCTAssertTrue(pres.isTotalPartial, "il totale limited è parziale, mai spacciato per totale")
    }

    // Accesso pieno → nessun banner, totale non parziale (contro-prova).
    func test_ready_fullAccessHasNoBannerAndTotalNotPartial() {
        let banner = DashboardBanner(showLimitedAccessBanner: false, isTotalPartial: false)
        let pres = DashboardPresentation(state: .ready(screen(categories: [], banner: banner)))

        XCTAssertFalse(pres.showsLimitedBanner)
        XCTAssertFalse(pres.isTotalPartial)
    }

    // failed → motivo esplicito e "Riprova", mai un verde finto o un blocco muto.
    func test_failed_reportsReasonAndOffersRetry() {
        let pres = DashboardPresentation(state: .failed("Errore di lettura dell'indice."))
        XCTAssertEqual(pres.kind, .failed)
        XCTAssertEqual(pres.detail, "Errore di lettura dell'indice.")
        XCTAssertTrue(pres.showsRetry)
        XCTAssertTrue(pres.categoryRows.isEmpty)
        XCTAssertNil(pres.reclaimable)
    }
}
