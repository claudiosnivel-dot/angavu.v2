import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — Report onesto: la presentazione PURA dello stato del report è
// l'oracolo della logica di schermata (quale hero, quali righe, quale onestà).
// La resa SwiftUI resta compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class HonestReportPresentationTests: XCTestCase {

    // Helper: costruisce uno stato `.ready` da pezzi di dominio, senza device.
    private func ready(
        categories: [CategoryBytes],
        reclaimable: ReclaimableSpace = ReclaimableSpace(reclaimableLibrarySpace: 0, reclaimableDeviceSpaceNow: 0),
        access: PhotoAccess = .full
    ) -> HonestReportState {
        let report = HonestReport(
            categories: categories,
            reclaimable: reclaimable,
            access: PhotoAccessPolicy.decide(for: access)
        )
        return .ready(HonestReportScreen(report: report))
    }

    // idle → schermata di caricamento, nessun hero, nessuna riga, nessun errore.
    func test_idle_isLoadingWithNoContent() {
        let pres = HonestReportPresentation(state: .idle)
        XCTAssertEqual(pres.kind, .idle)
        XCTAssertNil(pres.hero)
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
        let pres = HonestReportPresentation(state: ready(categories: categories))

        XCTAssertEqual(pres.kind, .ready)
        XCTAssertEqual(pres.categoryRows.map(\.category), [.photo, .video, .screenshot])
        XCTAssertEqual(pres.categoryRows.map(\.title), ["Foto", "Video", "Screenshot"])
        XCTAssertEqual(pres.categoryRows.first { $0.category == .photo }?.count, 3)
    }

    // AC-102-1 (hero): nulla stimato → hero esatto, col totale exact.
    func test_ready_heroIsExactWhenNothingEstimated() {
        let categories = [
            CategoryBytes(category: .photo, count: 2, exactBytes: 100, estimatedBytes: 0),
            CategoryBytes(category: .video, count: 1, exactBytes: 900, estimatedBytes: 0)
        ]
        let pres = HonestReportPresentation(state: ready(categories: categories))

        XCTAssertEqual(pres.hero?.isExact, true, "senza stime il totale è esatto")
        XCTAssertEqual(pres.hero?.bytes, 1000)
    }

    // AC-102-1 (hero): con una porzione stimata → hero marcato come stima, MAI
    // un unico totale spacciato per esatto; i byte sono exact + estimated.
    func test_ready_heroIsEstimateWhenAnyPortionEstimated() {
        let categories = [
            CategoryBytes(category: .photo, count: 2, exactBytes: 100, estimatedBytes: 50),
            CategoryBytes(category: .video, count: 1, exactBytes: 900, estimatedBytes: 0)
        ]
        let pres = HonestReportPresentation(state: ready(categories: categories))

        XCTAssertEqual(pres.hero?.isExact, false, "una stima non si fonde in un totale esatto")
        XCTAssertEqual(pres.hero?.bytes, 1050, "hero = byte exact + estimated, marcato come stima")
    }

    // Onestà per riga: una quota stimata è SEMPRE marcata; una tutta-exact no.
    func test_ready_marksEstimatedPortionPerCategory() {
        let categories = [
            CategoryBytes(category: .photo, count: 2, exactBytes: 100, estimatedBytes: 50),
            CategoryBytes(category: .video, count: 1, exactBytes: 1000, estimatedBytes: 0)
        ]
        let pres = HonestReportPresentation(state: ready(categories: categories))

        let photoRow = pres.categoryRows.first { $0.category == .photo }
        XCTAssertEqual(photoRow?.isEstimated, true, "la quota stimata non va nascosta")
        XCTAssertEqual(photoRow?.totalBytes, 150)

        let videoRow = pres.categoryRows.first { $0.category == .video }
        XCTAssertEqual(videoRow?.isEstimated, false, "una categoria interamente esatta non è marcata")
    }

    // AC-102-1 (caveat): device < libreria → caveat iCloud esposto, coi due numeri.
    func test_ready_surfacesICloudCaveatWhenDeviceFreesLessThanLibrary() {
        let reclaimable = ReclaimableSpace(reclaimableLibrarySpace: 1000, reclaimableDeviceSpaceNow: 400)
        let pres = HonestReportPresentation(state: ready(categories: [], reclaimable: reclaimable))

        XCTAssertEqual(pres.reclaimable?.libraryBytes, 1000)
        XCTAssertEqual(pres.reclaimable?.deviceBytesNow, 400)
        XCTAssertEqual(pres.reclaimable?.iCloudCaveat, true, "il caveat iCloud non va nascosto")
        XCTAssertTrue(pres.iCloudCaveat)
    }

    // Device == libreria → nessun caveat (contro-prova).
    func test_ready_noICloudCaveatWhenDeviceFreesAll() {
        let reclaimable = ReclaimableSpace(reclaimableLibrarySpace: 1000, reclaimableDeviceSpaceNow: 1000)
        let pres = HonestReportPresentation(state: ready(categories: [], reclaimable: reclaimable))

        XCTAssertEqual(pres.reclaimable?.iCloudCaveat, false)
        XCTAssertFalse(pres.iCloudCaveat)
    }

    // AC-102-2: accesso limited → banner parziale e invito all'accesso completo.
    func test_ready_limitedAccessMarksPartialAndInvitesFullAccess() {
        let pres = HonestReportPresentation(state: ready(categories: [], access: .limited))
        XCTAssertTrue(pres.showsPartialBanner, "il conteggio limited è parziale, mai un totale")
        XCTAssertTrue(pres.invitesFullAccess)
    }

    // Accesso pieno → nessun banner parziale, nessun invito (contro-prova).
    func test_ready_fullAccessHasNoPartialBannerNorInvite() {
        let pres = HonestReportPresentation(state: ready(categories: [], access: .full))
        XCTAssertFalse(pres.showsPartialBanner)
        XCTAssertFalse(pres.invitesFullAccess)
    }

    // failed → motivo esplicito e "Riprova", mai un verde finto o un blocco muto.
    func test_failed_reportsReasonAndOffersRetry() {
        let pres = HonestReportPresentation(state: .failed("Errore di lettura dell'indice."))
        XCTAssertEqual(pres.kind, .failed)
        XCTAssertEqual(pres.detail, "Errore di lettura dell'indice.")
        XCTAssertTrue(pres.showsRetry)
        XCTAssertNil(pres.hero)
        XCTAssertTrue(pres.categoryRows.isEmpty)
        XCTAssertNil(pres.reclaimable)
    }

    // R-03 — VoiceOver: la riga categoria è un solo elemento leggibile — titolo
    // come etichetta, conteggio + byte (formattati dalla View) come valore, con
    // la stima marcata anche all'ascolto e il singolare coniugato.
    func test_categoryRow_accessibility_labelAndValue() {
        let exact = HonestReportPresentation.CategoryRow(
            category: .photo, title: "Foto", count: 3, totalBytes: 300, isEstimated: false
        )
        XCTAssertEqual(exact.accessibilityLabel, "Foto")
        XCTAssertEqual(exact.accessibilityValue(formattedBytes: "300 byte"), "3 elementi, 300 byte")

        let estimatedSingular = HonestReportPresentation.CategoryRow(
            category: .video, title: "Video", count: 1, totalBytes: 900, isEstimated: true
        )
        XCTAssertEqual(estimatedSingular.accessibilityValue(formattedBytes: "900 byte"),
                       "1 elemento, 900 byte, stima")
    }
}
