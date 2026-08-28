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

    // Il riempimento è la frazione UNIFICATA reale, mai fabbricata: metà della 2ª fase
    // (byte) → una fase intera + mezza fase = 1.5/N. FSE-G1: N = 7 fasi (2 numeri + 5
    // rilevatori; la residenza è differita, fuori dalla barra), quindi 1.5/7. L'atteso è
    // derivato dal numero di fasi, non hardcoded, così resta vero se la pipeline cambia.
    func test_scanning_fillIsUnifiedRealFraction() {
        let stageCount = Double(ScanPipelineProgress.Stage.allCases.count)
        let pipeline = ScanPipelineProgress(
            stage: .resolvingSizes,
            stageProgress: AnalysisProgress(processed: 50, total: 100)
        )
        let flow = ScanFlowPresentation(state: .scanning(pipeline))
        XCTAssertEqual(flow.fill ?? -1, 1.5 / stageCount, accuracy: 0.0001)
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

    // MARK: - FSE-F2 — progresso onesto multi-fase + carosello su tutte le fasi

    private var stageCount: Double { Double(ScanPipelineProgress.Stage.allCases.count) }

    // AC-FSE-F2-1 — in fase 'similar' il titolo NOMINA onestamente l'attività corrente,
    // e la frazione è quella REALE della fase (unificata), mai fabbricata.
    func test_similarPhase_honestTitleAndRealFraction() {
        let pipeline = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos,
            stageProgress: AnalysisProgress(processed: 2, total: 4)
        )
        let flow = ScanFlowPresentation(state: .scanning(pipeline))

        XCTAssertEqual(flow.stageTitle, "Confronto le foto simili…", "il titolo nomina la fase corrente")
        XCTAssertEqual(flow.statusLabel, "2 di 4", "il conteggio è quello reale della fase")
        // Frazione unificata reale: (indice della fase + frazione della fase) / n fasi.
        let expected = (Double(ScanPipelineProgress.Stage.analyzingSimilarPhotos.rawValue) + 0.5) / stageCount
        XCTAssertEqual(flow.fill ?? -1, expected, accuracy: 0.0001, "frazione reale della fase, mai fabbricata")
        XCTAssertFalse(flow.isIndeterminate, "in analisi il progresso è determinato")
    }

    // AC-FSE-F2-2 — una fase a totale NULLO (categoria vuota) è trattata come COMPLETA
    // senza incollare la barra: la frazione arriva al confine della fase successiva,
    // coerente con ScanPipelineProgress (AnalysisProgress: total 0 ⇒ fraction 1).
    func test_emptyPhase_treatedAsCompleteWithoutStickingBar() {
        let stage = ScanPipelineProgress.Stage.analyzingExactDuplicates
        let pipeline = ScanPipelineProgress(
            stage: stage,
            stageProgress: AnalysisProgress(processed: 0, total: 0)   // categoria vuota
        )
        let flow = ScanFlowPresentation(state: .scanning(pipeline))

        let phaseStart = Double(stage.rawValue) / stageCount
        let phaseEnd = Double(stage.rawValue + 1) / stageCount
        XCTAssertEqual(flow.fill ?? -1, phaseEnd, accuracy: 0.0001, "fase vuota = completa, barra al confine")
        XCTAssertGreaterThan(flow.fill ?? -1, phaseStart, "non incollata all'inizio della fase")
        XCTAssertEqual(flow.stageTitle, "Cerco i duplicati…", "il titolo resta onesto anche a totale nullo")
    }

    // DoD FSE-F2 — il carosello resta attivo per TUTTE le fasi, e OGNI fase ha un
    // titolo onesto non vuoto (i rilevatori inclusi): l'unica attesa lunga resta leggibile.
    func test_carouselAndHonestTitleForEveryStage() {
        for stage in ScanPipelineProgress.Stage.allCases {
            let pipeline = ScanPipelineProgress(
                stage: stage,
                stageProgress: AnalysisProgress(processed: 1, total: 4)
            )
            let flow = ScanFlowPresentation(state: .scanning(pipeline))
            XCTAssertTrue(flow.showsCarousel, "carosello attivo in fase \(stage)")
            XCTAssertEqual(flow.isButtonEnabled, false, "tasto non toccabile durante il lavoro (\(stage))")
            let title = flow.stageTitle ?? ""
            XCTAssertFalse(title.isEmpty, "titolo di fase onesto non vuoto per \(stage)")
        }
    }
}
