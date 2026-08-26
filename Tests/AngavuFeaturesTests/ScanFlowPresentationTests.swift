import XCTest
import AngavuDomain
@testable import AngavuFeatures

// E-1 — Il flusso "Shazam" a tasto unico è pilotato dal layer PURO: quale fase,
// se il tasto è toccabile, se il progresso è determinato, se il carosello è su.
// La resa SwiftUI (tasto animato, battito, riempimento) resta compilata-ma-non-resa
// (L-COL-006); qui si prova la mappa e l'invariante d'onestà del progresso.

final class ScanFlowPresentationTests: XCTestCase {

    // idle → tasto gigante toccabile, nessun carosello, nessun progresso.
    func test_idle_readyTappableButton() {
        let flow = ScanFlowPresentation(state: .idle)
        XCTAssertEqual(flow.phase, .ready)
        XCTAssertTrue(flow.isButtonEnabled)
        XCTAssertEqual(flow.buttonTitle, "Analizza la libreria")
        XCTAssertNotNil(flow.buttonCaption)
        XCTAssertFalse(flow.showsCarousel)
        XCTAssertNil(flow.fill)
        XCTAssertNil(flow.statusLabel)
    }

    // requestingPermission → fase "preparing" INDETERMINATA: battito, mai una
    // frazione fabbricata; carosello mostrato; tasto non toccabile.
    func test_requestingPermission_indeterminateHeartbeatNoFabricatedFill() {
        let flow = ScanFlowPresentation(state: .requestingPermission)
        XCTAssertEqual(flow.phase, .preparing)
        XCTAssertFalse(flow.isButtonEnabled)
        XCTAssertTrue(flow.isIndeterminate)
        XCTAssertNil(flow.fill, "In fase permesso il riempimento non è fabbricato")
        XCTAssertTrue(flow.showsCarousel)
        XCTAssertNotNil(flow.statusLabel)
    }

    // scanning → fase determinata: il riempimento è la frazione UNIFICATA reale
    // (sull'intera pipeline), il conteggio è quello reale della fase, la fase è nominata.
    func test_scanning_determinateFillFromRealProgress() {
        let pipeline = ScanPipelineProgress(
            stage: .resolvingSizes,
            stageProgress: AnalysisProgress(processed: 3, total: 12)
        )
        let flow = ScanFlowPresentation(state: .scanning(pipeline))
        XCTAssertEqual(flow.phase, .scanning)
        XCTAssertFalse(flow.isIndeterminate)
        XCTAssertEqual(flow.fill, pipeline.fraction)
        XCTAssertTrue(flow.showsCarousel)
        XCTAssertFalse(flow.isButtonEnabled)
        XCTAssertEqual(flow.statusLabel, "3 di 12")
        XCTAssertNotNil(flow.stageTitle, "La fase corrente è nominata sotto il conteggio")
        XCTAssertTrue(flow.canCancel, "L'analisi è interrompibile (stop cooperativo)")
    }

    // Solo l'analisi vera è annullabile: riposo, permesso ed esiti terminali no.
    func test_onlyScanningIsCancellable() {
        let pipeline = ScanPipelineProgress(stage: .indexing, stageProgress: AnalysisProgress(processed: 1, total: 2))
        XCTAssertFalse(ScanFlowPresentation(state: .idle).canCancel)
        XCTAssertFalse(ScanFlowPresentation(state: .requestingPermission).canCancel)
        XCTAssertTrue(ScanFlowPresentation(state: .scanning(pipeline)).canCancel)
        XCTAssertFalse(ScanFlowPresentation(state: .completed(indexed: 1, partialCount: false)).canCancel)
        XCTAssertFalse(ScanFlowPresentation(state: .failed("x")).canCancel)
        XCTAssertFalse(ScanFlowPresentation(state: .cancelled(AnalysisProgress(processed: 1, total: 2))).canCancel)
    }

    // Il riempimento è la frazione UNIFICATA reale, mai fabbricata: metà della fase
    // centrale (di tre) → una fase intera + mezza fase = 1.5/3 = 0.5.
    func test_scanning_fillIsUnifiedRealFraction() {
        let pipeline = ScanPipelineProgress(
            stage: .resolvingSizes,
            stageProgress: AnalysisProgress(processed: 50, total: 100)
        )
        let flow = ScanFlowPresentation(state: .scanning(pipeline))
        XCTAssertEqual(flow.fill ?? -1, 0.5, accuracy: 0.0001)
    }

    // completed → esito terminale: il flusso cede alla schermata di risultato (E-3).
    func test_completed_isFinishedHandsOffToResult() {
        let flow = ScanFlowPresentation(state: .completed(indexed: 42, partialCount: false))
        XCTAssertEqual(flow.phase, .finished)
        XCTAssertFalse(flow.isButtonEnabled)
        XCTAssertFalse(flow.showsCarousel)
    }

    // failed → esito terminale: il flusso cede alla schermata di risultato (E-3).
    func test_failed_isFinishedHandsOffToResult() {
        let flow = ScanFlowPresentation(state: .failed("Errore di lettura."))
        XCTAssertEqual(flow.phase, .finished)
        XCTAssertFalse(flow.showsCarousel)
    }

    // cancelled → torna al tasto (ready) riprovabile, con nota "niente modificato".
    func test_cancelled_returnsToReadyRetry() {
        let progress = AnalysisProgress(processed: 5, total: 20)
        let flow = ScanFlowPresentation(state: .cancelled(progress))
        XCTAssertEqual(flow.phase, .ready)
        XCTAssertTrue(flow.isButtonEnabled)
        XCTAssertEqual(flow.buttonTitle, "Riprova")
        XCTAssertFalse(flow.showsCarousel)
        XCTAssertTrue(flow.buttonCaption?.contains("Niente è stato modificato") ?? false)
    }
}
