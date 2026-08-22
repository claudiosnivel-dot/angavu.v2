import XCTest
@testable import AngavuDomain
@testable import AngavuFeatures

// T-101 — AC-101-1 / AC-101-2. La navigazione rispetta il gate di anteprima:
// nessun percorso raggiunge l'eliminazione saltando lo stato `previewing`.

final class NavigationPreviewGateTests: XCTestCase {

    // AC-101-1: seguendo il percorso di una sezione fino alla conferma, si passa
    // dallo stato `previewing` PRIMA di `confirmed` (gate rispettato).
    func test_sectionRoutePassesPreviewingBeforeConfirmed() throws {
        let trace = try XCTUnwrap(
            SectionNavigator.deletionRoute(for: .exactDuplicates, selecting: ["a", "b"])
        )

        XCTAssertTrue(trace.reachedConfirmed, "il percorso arriva alla conferma")
        XCTAssertTrue(trace.passedThroughPreviewing, "passa dall'anteprima")
        XCTAssertTrue(trace.previewingPrecededConfirmed, "previewing deve precedere confirmed")
        XCTAssertTrue(trace.reachedDeleting, "e prosegue fino all'eliminazione")
    }

    // AC-101-2: enumerando TUTTI i percorsi che portano a un'eliminazione, ognuno
    // include lo stato `previewing` — nessuno lo salta.
    func test_everyDeletionPathIncludesPreviewing() {
        let sections = AppSection.assetDeletingSections
        XCTAssertFalse(sections.isEmpty, "ci sono sezioni che eliminano asset")

        for section in sections {
            let route = SectionNavigator.deletionRoute(for: section, selecting: ["x"])
            XCTAssertNotNil(route, "\(section) è una sezione di eliminazione")
            XCTAssertTrue(
                route?.passedThroughPreviewing == true,
                "\(section): il percorso di eliminazione deve passare dall'anteprima"
            )
            XCTAssertTrue(
                route?.previewingPrecededConfirmed == true,
                "\(section): l'anteprima precede la conferma"
            )
        }
    }

    // Le sezioni di sola lettura (dashboard) non espongono un percorso di
    // eliminazione: niente route, niente eliminazione da lì.
    func test_readOnlySectionsHaveNoDeletionRoute() {
        XCTAssertNil(SectionNavigator.deletionRoute(for: .dashboard, selecting: ["a"]))
    }

    // Guardia sul gate: chiamando direttamente il DeletionFlow, non è possibile
    // raggiungere `confirmed` senza prima aver mostrato E accettato l'anteprima.
    // Se il gate fosse aggirabile la traccia lo mostrerebbe (oracolo non vacuo).
    func test_gateCannotBeSkipped() {
        var flow = DeletionFlow()
        // Tentare la conferma da idle è rifiutato: nessuna transizione.
        XCTAssertFalse(flow.confirm())
        XCTAssertEqual(flow.state, .idle)

        // Anche dopo aver mostrato l'anteprima ma senza accettarla, confirm fallisce.
        XCTAssertTrue(flow.presentPreview(for: ["a"]))
        XCTAssertFalse(flow.confirm(), "senza accettazione non si conferma")
    }

    // Selezione vuota: il percorso non parte nemmeno (l'anteprima richiede
    // asset selezionati) → non raggiunge la conferma.
    func test_emptySelectionDoesNotReachConfirmed() {
        let route = SectionNavigator.deletionRoute(for: .similarPhotos, selecting: [])
        XCTAssertNotNil(route)
        XCTAssertFalse(route?.reachedConfirmed == true, "senza selezione non si conferma")
    }
}
