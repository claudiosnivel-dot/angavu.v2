import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — schermata «Comprimi video»: oracolo della presentazione pura.
// Ogni `CompressionState` mappa a una e una sola presentazione, con gli invarianti
// di onestà: stima marcata, consenso opt-in offerto solo dopo la stima, originale
// verso la rete di sicurezza a completamento.

final class CompressionPresentationTests: XCTestCase {

    private func doneReplacement(outputBytes: Int64) -> CompressedReplacement {
        let outcome = VideoExportOutcome.success(
            outputBytes: outputBytes,
            metadata: VideoMetadata(creationDate: nil, latitude: nil, longitude: nil)
        )
        let planned = CompressedReplacementPlanner.plan(
            outcome: outcome,
            exportVerifiedIntegral: true,
            previewConfirmed: true,
            originalId: "V1"
        )
        guard case .success(let replacement) = planned else {
            fatalError("setup: piano di sostituzione atteso valido")
        }
        return replacement
    }

    func test_idle_offersNothingAndHasNoEstimate() {
        let pres = CompressionPresentation(state: .idle)
        XCTAssertEqual(pres.phase, .idle)
        XCTAssertFalse(pres.offersConsent)
        XCTAssertFalse(pres.offersCompression)
        XCTAssertFalse(pres.isWorking)
        XCTAssertNil(pres.estimatedSavingBytes)
        XCTAssertNil(pres.safetyNote)
    }

    // AC-080-1 (presentazione): il risparmio è mostrato ed è SEMPRE una stima; il
    // consenso opt-in è offerto qui e SOLO qui.
    func test_estimated_showsEstimateAndOffersConsentOnly() {
        let pres = CompressionPresentation(state: .estimated(.estimated(bytes: 300)))
        XCTAssertEqual(pres.phase, .estimated)
        XCTAssertEqual(pres.estimatedSavingBytes, 300)
        XCTAssertTrue(pres.offersConsent, "il consenso opt-in si offre dopo la stima")
        XCTAssertFalse(pres.offersCompression, "l'avvio non è ancora offerto")
        XCTAssertFalse(pres.isWorking)
    }

    // AC-080-2 (presentazione): l'avvio della compressione è offerto SOLO col
    // consenso registrato, mai prima.
    func test_consented_offersCompressionNotConsent() {
        let pres = CompressionPresentation(state: .consented(assets: ["V1"]))
        XCTAssertEqual(pres.phase, .consented)
        XCTAssertTrue(pres.offersCompression)
        XCTAssertFalse(pres.offersConsent, "il consenso non si richiede due volte")
        XCTAssertFalse(pres.isWorking)
    }

    func test_exporting_isWorking() {
        let pres = CompressionPresentation(state: .exporting("V1"))
        XCTAssertEqual(pres.phase, .working)
        XCTAssertTrue(pres.isWorking)
        XCTAssertFalse(pres.offersConsent)
        XCTAssertFalse(pres.offersCompression)
    }

    func test_replacing_isWorking() {
        let pres = CompressionPresentation(state: .replacing("V1"))
        XCTAssertEqual(pres.phase, .working)
        XCTAssertTrue(pres.isWorking)
    }

    // AC-082-1 (presentazione): a completamento l'output è mostrato e la nota della
    // rete di sicurezza è presente (originale recuperabile).
    func test_done_showsOutputAndSafetyNote() {
        let pres = CompressionPresentation(state: .done(doneReplacement(outputBytes: 500)))
        XCTAssertEqual(pres.phase, .done)
        XCTAssertEqual(pres.compressedOutputBytes, 500)
        XCTAssertNotNil(pres.safetyNote)
        XCTAssertFalse(pres.isWorking)
        XCTAssertFalse(pres.offersRetry)
    }

    func test_cancelled_isTerminalSourceIntact() {
        let pres = CompressionPresentation(state: .cancelled)
        XCTAssertEqual(pres.phase, .cancelled)
        XCTAssertFalse(pres.isWorking)
        XCTAssertFalse(pres.offersRetry)
        XCTAssertNotNil(pres.detail)
    }

    func test_failed_showsReasonAndOffersRetry() {
        let pres = CompressionPresentation(state: .failed("boom"))
        XCTAssertEqual(pres.phase, .failed)
        XCTAssertEqual(pres.detail, "boom")
        XCTAssertTrue(pres.offersRetry)
        XCTAssertFalse(pres.isWorking)
    }
}
