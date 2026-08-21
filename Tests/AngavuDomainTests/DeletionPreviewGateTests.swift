import XCTest
@testable import AngavuDomain

// T-050 — AC-050-1 / AC-050-2. Gate di anteprima obbligatoria prima di eliminare.

final class DeletionPreviewGateTests: XCTestCase {

    // AC-050-1: da idle con asset selezionati, tentare direttamente `confirmed`
    // saltando l'anteprima → transizione rifiutata (gate obbligatorio).
    func test_confirmWithoutPreview_isRejected() {
        var flow = DeletionFlow()
        XCTAssertEqual(flow.state, .idle)

        // Selezione presente, ma nessuna anteprima mostrata/accettata.
        let confirmed = flow.confirm()

        XCTAssertFalse(confirmed, "confirm senza anteprima deve essere rifiutato")
        XCTAssertEqual(flow.state, .idle, "lo stato resta idle: nessun salto del gate")
    }

    // Anche un'anteprima mostrata ma NON accettata non basta a confermare.
    func test_confirmWithUnacceptedPreview_isRejected() {
        var flow = DeletionFlow()
        XCTAssertTrue(flow.presentPreview(for: ["A", "B"]))

        let confirmed = flow.confirm()

        XCTAssertFalse(confirmed, "confirm richiede un'anteprima accettata")
        XCTAssertEqual(flow.state, .previewing(assets: ["A", "B"], accepted: false))
    }

    // AC-050-2: anteprima mostrata e accettata → confirm consentito, e l'insieme
    // da eliminare coincide con quello previewato.
    func test_confirmAfterAcceptedPreview_isAllowedAndPreservesSet() {
        var flow = DeletionFlow()
        let selected = ["A", "B", "C"]

        XCTAssertTrue(flow.presentPreview(for: selected))
        XCTAssertTrue(flow.acceptPreview())
        let confirmed = flow.confirm()

        XCTAssertTrue(confirmed, "confirm dopo anteprima accettata deve essere consentito")
        XCTAssertEqual(flow.state, .confirmed(assets: selected))
        XCTAssertEqual(flow.pendingAssets, selected, "l'insieme confermato coincide col previewato")
    }

    // Un'anteprima su selezione vuota non è ammessa: niente da eliminare.
    func test_previewOnEmptySelection_isRejected() {
        var flow = DeletionFlow()
        XCTAssertFalse(flow.presentPreview(for: []))
        XCTAssertEqual(flow.state, .idle)
    }

    // Percorso completo fino a deleting, solo per transizioni legali in sequenza.
    func test_fullLegalPath() {
        var flow = DeletionFlow()
        XCTAssertTrue(flow.presentPreview(for: ["X"]))
        XCTAssertTrue(flow.acceptPreview())
        XCTAssertTrue(flow.confirm())
        XCTAssertTrue(flow.beginDeleting())
        XCTAssertEqual(flow.state, .deleting(assets: ["X"]))
    }
}
