import XCTest
@testable import AngavuDomain

// T-082 — AC-082-1 / AC-082-2. Sostituzione solo dopo export verificato + anteprima.

final class CompressedReplacementTests: XCTestCase {

    private let meta = VideoMetadata(
        creationDate: Date(timeIntervalSince1970: 1_000),
        latitude: 45.07,
        longitude: 7.68
    )

    // AC-082-1: export success verificato + anteprima confermata → originale
    // eliminato via DeletionFlow (portato a confirmed) e compresso pronto all'indice.
    func test_replacement_approvedRoutesOriginalThroughDeletionFlow() {
        let url = URL(fileURLWithPath: "/tmp/out.mov")
        let outcome = VideoExportOutcome.success(outputBytes: 80_000_000, outputURL: url, metadata: meta)

        let result = CompressedReplacementPlanner.plan(
            outcome: outcome,
            exportVerifiedIntegral: true,
            previewConfirmed: true,
            originalId: "vid1"
        )

        guard case .success(let replacement) = result else {
            return XCTFail("attesa sostituzione approvata, ottenuto \(result)")
        }
        XCTAssertEqual(replacement.originalId, "vid1")
        XCTAssertEqual(replacement.compressed.outputBytes, 80_000_000)
        XCTAssertEqual(replacement.compressed.metadata, meta)
        // L'eliminazione passa dal gate della rete di sicurezza: confermata su [vid1].
        XCTAssertEqual(replacement.deletion.state, .confirmed(assets: ["vid1"]))
    }

    // AC-082-2: export non verificato integro → sostituzione rifiutata, originale intatto.
    func test_replacement_refusedWhenExportNotVerified() {
        let url = URL(fileURLWithPath: "/tmp/out.mov")
        let outcome = VideoExportOutcome.success(outputBytes: 80_000_000, outputURL: url, metadata: meta)

        let result = CompressedReplacementPlanner.plan(
            outcome: outcome,
            exportVerifiedIntegral: false,   // non verificato
            previewConfirmed: true,
            originalId: "vid1"
        )

        XCTAssertEqual(result, .failure(.exportNotVerified))
    }

    // Un export fallito non può mai portare a sostituzione.
    func test_replacement_refusedWhenExportFailed() {
        let result = CompressedReplacementPlanner.plan(
            outcome: .failed(reason: "boom"),
            exportVerifiedIntegral: true,
            previewConfirmed: true,
            originalId: "vid1"
        )
        XCTAssertEqual(result, .failure(.exportNotVerified))
    }

    // Senza conferma dell'anteprima la sostituzione è rifiutata, prima ancora
    // di guardare l'export.
    func test_replacement_refusedWhenPreviewNotConfirmed() {
        let url = URL(fileURLWithPath: "/tmp/out.mov")
        let outcome = VideoExportOutcome.success(outputBytes: 80_000_000, outputURL: url, metadata: meta)
        let result = CompressedReplacementPlanner.plan(
            outcome: outcome,
            exportVerifiedIntegral: true,
            previewConfirmed: false,
            originalId: "vid1"
        )
        XCTAssertEqual(result, .failure(.previewNotConfirmed))
    }
}
