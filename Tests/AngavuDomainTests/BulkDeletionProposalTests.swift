import XCTest
@testable import AngavuDomain

// T-062 — AC-062-1 / AC-062-2. Proposta di eliminazione in blocco che confluisce
// nel gate di anteprima obbligatoria (T-050). Domain puro.

final class BulkDeletionProposalTests: XCTestCase {

    private func asset(_ id: String, kind: MediaKind = .video, screenshot: Bool = false) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: kind,
            pixelSize: PixelSize(width: 1920, height: 1080),
            creationDate: nil,
            subtypes: screenshot ? [.screenshot] : []
        )
    }

    // AC-062-1: una selezione di 4 asset (video + screenshot) → removable contiene
    // i 4, keep è vuoto (categoria a eliminazione diretta).
    func test_composesBulkProposalAllRemovableNoKeep() {
        let selection = [
            asset("video-1"),
            asset("video-2"),
            asset("shot-1", kind: .photo, screenshot: true),
            asset("shot-2", kind: .photo, screenshot: true)
        ]

        let proposal = BulkDeletionProposalComposer.compose(from: selection)

        XCTAssertEqual(proposal.removable.map(\.id), ["video-1", "video-2", "shot-1", "shot-2"])
        XCTAssertTrue(proposal.keep.isEmpty)
        XCTAssertEqual(proposal.removableIds, ["video-1", "video-2", "shot-1", "shot-2"])
    }

    // AC-062-2: passata al DeletionFlow, il flusso richiede l'anteprima prima di
    // consentire la conferma (gate T-050). Nessuna eliminazione in autonomia.
    func test_bulkProposalEntersMandatoryPreviewGate() {
        let selection = [asset("a"), asset("b"), asset("c"), asset("d")]
        let proposal = BulkDeletionProposalComposer.compose(from: selection)

        var flow = BulkDeletionProposalComposer.presentInSafetyNet(proposal)

        // Entra in previewing con esattamente gli asset della proposta.
        XCTAssertEqual(flow.pendingAssets, ["a", "b", "c", "d"])
        // Gate: senza accettazione dell'anteprima non si può confermare.
        XCTAssertFalse(flow.confirm())
        // Solo dopo aver accettato l'anteprima la conferma è consentita.
        XCTAssertTrue(flow.acceptPreview())
        XCTAssertTrue(flow.confirm())
        XCTAssertEqual(flow.pendingAssets, ["a", "b", "c", "d"])
    }

    // Rafforza il gate: un DeletionFlow fresco non può confermare la proposta
    // saltando del tutto l'anteprima (nessun percorso diretto all'eliminazione).
    func test_cannotConfirmWithoutPresentingPreview() {
        var flow = DeletionFlow()
        XCTAssertFalse(flow.confirm())
        XCTAssertFalse(flow.beginDeleting())
    }

    // Una selezione vuota lascia il flusso in idle: nulla da eliminare.
    func test_emptySelectionLeavesFlowIdle() {
        let proposal = BulkDeletionProposalComposer.compose(from: [])
        let flow = BulkDeletionProposalComposer.presentInSafetyNet(proposal)
        XCTAssertTrue(flow.pendingAssets.isEmpty)
    }
}
