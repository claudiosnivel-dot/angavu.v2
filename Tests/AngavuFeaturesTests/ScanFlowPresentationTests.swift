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
    // (sull'intera pipeline), l'etichetta è la percentuale onesta della barra unificata
    // (mai il conteggio grezzo per-fase), la fase è nominata.
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
        let expectedPercent = "\(Int((pipeline.fraction * 100).rounded()))%"
        XCTAssertEqual(flow.statusLabel, expectedPercent, "la percentuale della barra unificata")
        XCTAssertFalse(flow.statusLabel?.contains(" di ") ?? true, "mai il denominatore grezzo per-fase")
        XCTAssertNotNil(flow.stageTitle, "La fase corrente è nominata sotto la percentuale")
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
        XCTAssertEqual(
            flow.statusLabel, "\(Int((pipeline.fraction * 100).rounded()))%",
            "la percentuale della barra unificata, non il conteggio grezzo della fase"
        )
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

    // MARK: - FSE-I2 follow-up — etichetta di progresso stabile e onesta (percentuale)

    // Il difetto: durante «foto simili» le sotto-fasi usano `total` interni diversi
    // (composizione dHash = 2·N, keep-best = N+M) per la matematica della barra; esposti
    // come "X di N" il denominatore saltava e SUPERAVA il conteggio foto reale, violando
    // «numeri veri». Qui l'oracolo del fix: l'etichetta di scanning è una percentuale
    // della barra unificata, mai un denominatore grezzo per-fase.

    // Nessun denominatore grezzo in NESSUNA fase: l'etichetta è sempre una percentuale.
    func test_scanning_statusLabelIsPercentNeverRawDenominator() {
        for stage in ScanPipelineProgress.Stage.allCases {
            let pipeline = ScanPipelineProgress(
                stage: stage,
                stageProgress: AnalysisProgress(processed: 45_000, total: 90_000)   // finti total "gonfi"
            )
            let label = ScanFlowPresentation(state: .scanning(pipeline)).statusLabel ?? ""
            XCTAssertTrue(label.hasSuffix("%"), "etichetta percentuale in fase \(stage): \(label)")
            XCTAssertFalse(label.contains(" di "), "nessun denominatore grezzo in fase \(stage): \(label)")
        }
    }

    // AC-1 — STABILITÀ al confine delle sotto-fasi simili: a parità di frazione della
    // barra, `total` interni diversi (2·N vs N+M) danno la STESSA etichetta. Prima il
    // denominatore trasparivano e saltava; ora non traspare più.
    func test_similarSubphases_sameFractionSameLabel_despiteDifferentInternalTotals() {
        // Composizione a metà: 22_500 / 45_000 (=2·N) → frazione di fase 0.5.
        let composition = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos,
            stageProgress: AnalysisProgress(processed: 22_500, total: 45_000)
        )
        // Keep-best allo stesso punto di fase 0.5 ma con total N+M diverso: 14_000 / 28_000.
        let keepBest = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos,
            stageProgress: AnalysisProgress(processed: 14_000, total: 28_000)
        )
        let compositionLabel = ScanFlowPresentation(state: .scanning(composition)).statusLabel
        let keepBestLabel = ScanFlowPresentation(state: .scanning(keepBest)).statusLabel
        XCTAssertEqual(
            compositionLabel, keepBestLabel,
            "stessa frazione ⇒ stessa etichetta: il denominatore per-sotto-fase non traspare"
        )
    }

    // AC-2 — MONOTONÌA percepita: passando composizione → keep-best (frazione che sale)
    // la percentuale mostrata non cala mai, benché i `total` interni cambino/diminuiscano.
    func test_similarSubphases_percentNeverDecreasesAcrossBoundary() {
        // Fine composizione (headroom): 45_000 / 45_000 → frazione di fase 1.0? No: la
        // composizione riserva l'headroom in CategoryReviewSource; qui simuliamo la barra
        // UNIFICATA a due istanti crescenti sulla stessa fase, con total interni diversi.
        let earlier = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos,
            stageProgress: AnalysisProgress(processed: 30_000, total: 45_000)   // 0.666… di fase
        )
        let later = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos,
            stageProgress: AnalysisProgress(processed: 21_000, total: 28_000)   // 0.75 di fase, total minore
        )
        func percent(_ pipe: ScanPipelineProgress) -> Int {
            let label = ScanFlowPresentation(state: .scanning(pipe)).statusLabel ?? "0%"
            return Int(label.dropLast()) ?? -1
        }
        XCTAssertGreaterThan(later.fraction, earlier.fraction, "la barra unificata sale")
        XCTAssertGreaterThanOrEqual(
            percent(later), percent(earlier),
            "la percentuale non cala mai al confine, nonostante il total interno diminuisca"
        )
    }

    // AC-3 — ONESTÀ: la percentuale riflette round(fraction·100) e non supera mai 100 %,
    // anche con `processed` > `total` (frazione clampata a 1) — mai un numero fabbricato/gonfio.
    func test_scanning_percentReflectsFractionAndNeverExceeds100() throws {
        let stageCount = Double(ScanPipelineProgress.Stage.allCases.count)
        // Caso normale: metà della fase 'indexing'.
        let mid = ScanPipelineProgress(stage: .indexing, stageProgress: AnalysisProgress(processed: 1, total: 2))
        let expectedMid = Int(((0.5 / stageCount) * 100).rounded())
        XCTAssertEqual(ScanFlowPresentation(state: .scanning(mid)).statusLabel, "\(expectedMid)%")

        // Ultima fase completa → 100 %, mai oltre.
        let last = try XCTUnwrap(ScanPipelineProgress.Stage.allCases.last)
        let done = ScanPipelineProgress(stage: last, stageProgress: AnalysisProgress(processed: 10, total: 10))
        XCTAssertEqual(ScanFlowPresentation(state: .scanning(done)).statusLabel, "100%", "fase finale completa = 100 %")

        // `AnalysisProgress` clampa già `processed` a `total` (fraction ≤ 1 per costruzione),
        // e ogni fase pesa 1/N: la frazione unificata è ≤ 1 in ogni caso, quindi la
        // percentuale non supera mai il 100 % — mai un numero gonfiato come col vecchio 2·N.
        let overshoot = ScanPipelineProgress(stage: last, stageProgress: AnalysisProgress(processed: 20, total: 10))
        let label = ScanFlowPresentation(state: .scanning(overshoot)).statusLabel ?? ""
        XCTAssertEqual(label, "100%", "mai oltre il 100 %: la barra unificata è ≤ 1 per costruzione")
    }
}
