import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — Review di categoria: la presentazione PURA (review + stato del gate)
// è l'oracolo della logica di schermata (quali righe, quale fase, quando è offerta
// l'azione «Elimina», cosa entra in anteprima/conferma). La resa SwiftUI resta
// compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class CategoryReviewPresentationTests: XCTestCase {

    private func present(
        _ review: CategoryReview,
        flow: DeletionFlow.State = .idle
    ) -> CategoryReviewPresentation {
        CategoryReviewPresentation(review: review, flowState: flow, title: "Screenshot", subtitle: "sub")
    }

    // idle → si rivede: righe mappate con la giusta disposizione, ordine keep→removable.
    func test_reviewing_mapsRowsWithDisposition() {
        let pres = present(CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]))

        XCTAssertEqual(pres.phase, .reviewing)
        XCTAssertEqual(pres.keepRows, [.init(id: "K1", disposition: .keep)])
        XCTAssertEqual(pres.removableRows, [
            .init(id: "R1", disposition: .removable),
            .init(id: "R2", disposition: .removable)
        ])
        XCTAssertEqual(pres.keepCount, 1)
        XCTAssertEqual(pres.removableCount, 2)
    }

    // Onestà: l'azione «Elimina» è offerta SOLO mentre si rivede e c'è del removable.
    func test_canRequestDeletion_onlyWhileReviewingWithRemovable() {
        let withRemovable = present(CategoryReview(keepIds: ["K1"], removableIds: ["R1"]))
        XCTAssertTrue(withRemovable.canRequestDeletion)

        let noRemovable = present(CategoryReview(keepIds: ["K1"], removableIds: []))
        XCTAssertFalse(noRemovable.canRequestDeletion, "senza removable non si offre l'eliminazione")
    }

    // Stato vuoto: nessun keep e nessun removable → isEmpty, nessuna azione.
    func test_empty_whenNoRowsAtAll() {
        let pres = present(CategoryReview(keepIds: [], removableIds: []))
        XCTAssertTrue(pres.isEmpty)
        XCTAssertFalse(pres.canRequestDeletion)
        XCTAssertEqual(pres.removableCount, 0)
    }

    // Una lista di soli keep NON è «vuota» (c'è qualcosa), ma non offre l'eliminazione.
    func test_onlyKeep_isNotEmptyButOffersNoDeletion() {
        let pres = present(CategoryReview(keepIds: ["K1"], removableIds: []))
        XCTAssertFalse(pres.isEmpty)
        XCTAssertFalse(pres.canRequestDeletion)
    }

    // previewing → fase anteprima: l'insieme in anteprima è esposto, l'azione non
    // è più offerta (il gate è già aperto), nessun confermato.
    func test_previewing_exposesPreviewSetAndHidesAction() {
        let pres = present(
            CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]),
            flow: .previewing(assets: ["R1", "R2"], accepted: false)
        )
        XCTAssertEqual(pres.phase, .previewing)
        XCTAssertEqual(pres.previewAssetIds, ["R1", "R2"])
        XCTAssertEqual(pres.previewCount, 2)
        XCTAssertFalse(pres.canRequestDeletion)
        XCTAssertTrue(pres.confirmedAssetIds.isEmpty)
    }

    // confirmed → eliminazione autorizzata: l'insieme confermato è esposto, l'azione
    // non è offerta, nessun residuo in anteprima.
    func test_confirmed_exposesConfirmedSet() {
        let pres = present(
            CategoryReview(keepIds: [], removableIds: ["R1"]),
            flow: .confirmed(assets: ["R1"])
        )
        XCTAssertEqual(pres.phase, .confirmed)
        XCTAssertEqual(pres.confirmedAssetIds, ["R1"])
        XCTAssertEqual(pres.confirmedCount, 1)
        XCTAssertFalse(pres.canRequestDeletion)
        XCTAssertTrue(pres.previewAssetIds.isEmpty)
    }

    // deleting (esecuzione della rete di sicurezza, fuori scope T-113) è mappato,
    // dal punto di vista della schermata, come «confermato/autorizzato».
    func test_deleting_isPresentedAsConfirmed() {
        let pres = present(
            CategoryReview(keepIds: [], removableIds: ["R1"]),
            flow: .deleting(assets: ["R1"])
        )
        XCTAssertEqual(pres.phase, .confirmed)
        XCTAssertEqual(pres.confirmedAssetIds, ["R1"])
    }

    // La nota della rete di sicurezza è sempre presente (recupero di sistema onesto).
    func test_safetyNote_isAlwaysPresent() {
        let pres = present(CategoryReview(keepIds: [], removableIds: ["R1"]))
        XCTAssertFalse(pres.safetyNote.isEmpty)
    }

    // I titoli passati sono esposti (unica fonte del testo della categoria).
    func test_titleAndSubtitle_arePassedThrough() {
        let pres = CategoryReviewPresentation(
            review: CategoryReview(keepIds: [], removableIds: ["R1"]),
            flowState: .idle, title: "Screenshot", subtitle: "le catture di schermo"
        )
        XCTAssertEqual(pres.title, "Screenshot")
        XCTAssertEqual(pres.subtitle, "le catture di schermo")
    }
}
