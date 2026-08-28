import XCTest
import AngavuDomain

// Oracolo del progresso UNIFICATO della scansione: la barra unica non arretra mai
// passando di fase e la frazione è composta dalle frazioni REALI per-fase (mai
// fabbricata). FSE-F1: fasi equipesate — i numeri veri (indice → byte) e le cinque dei
// RILEVATORI di categoria (screenshot, duplicati, simili, sfocate, grandi/vecchi),
// calcolati nella stessa passata. FSE-G1 (strategia B): la MISURA della residenza device
// è uscita dalla barra (differita, fuori dal percorso obbligatorio) → SETTE fasi.

final class ScanPipelineProgressTests: XCTestCase {

    private let stageCount = Double(ScanPipelineProgress.Stage.allCases.count)

    // Inizio assoluto: prima fase a 0 → frazione complessiva 0.
    func test_startOfFirstStageIsZero() {
        let progress = ScanPipelineProgress(
            stage: .indexing, stageProgress: AnalysisProgress(processed: 0, total: 10)
        )
        XCTAssertEqual(progress.fraction, 0.0, accuracy: 0.0001)
    }

    // Fine assoluta: ULTIMA fase completa → frazione complessiva 1. L'ultima fase è ora
    // un rilevatore (grandi/vecchi): la barra si chiude solo quando anche le categorie
    // sono state calcolate, non più alla sola misura della residenza.
    func test_endOfLastStageIsOne() throws {
        let last = try XCTUnwrap(ScanPipelineProgress.Stage.allCases.last)
        XCTAssertEqual(last, .analyzingLargeOldVideos)
        let progress = ScanPipelineProgress(
            stage: last, stageProgress: AnalysisProgress(processed: 10, total: 10)
        )
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
    }

    // La fase dei numeri (byte) NON è la fine: restano le cinque fasi dei rilevatori.
    // Fine di `resolvingSizes` = 2/7, non 1 (nessuna barra "finita" prematura). FSE-G1:
    // la residenza non è più una fase della barra (differita).
    func test_resolvingSizesIsNotTheEnd() {
        let progress = ScanPipelineProgress(
            stage: .resolvingSizes, stageProgress: AnalysisProgress(processed: 10, total: 10)
        )
        XCTAssertEqual(progress.fraction, 2.0 / stageCount, accuracy: 0.0001)
        XCTAssertLessThan(progress.fraction, 1.0)
    }

    // AC-FSE-F1-3 — La frazione unificata è MONOTÒNA non decrescente su TUTTE le fasi,
    // dai numeri veri ai rilevatori: percorrendo ogni fase da 0 a completa, e passando
    // di fase, il valore complessivo non arretra MAI.
    func test_fractionIsMonotonicAcrossAllStagesIncludingDetectors() {
        var previous = -1.0
        for stage in ScanPipelineProgress.Stage.allCases {
            // Tre campioni entro la fase: inizio (0/4), metà (2/4), fine (4/4).
            for processed in [0, 2, 4] {
                let progress = ScanPipelineProgress(
                    stage: stage, stageProgress: AnalysisProgress(processed: processed, total: 4)
                )
                XCTAssertGreaterThanOrEqual(
                    progress.fraction, previous,
                    "la barra non deve arretrare a \(stage) \(processed)/4"
                )
                previous = progress.fraction
            }
        }
        // L'ultimo campione (ultima fase completa) è esattamente 1.
        XCTAssertEqual(previous, 1.0, accuracy: 0.0001)
    }

    // AC-FSE-F1-3 (confine) — il passaggio da una fase RILEVATORE alla successiva non
    // arretra: fine dei duplicati == inizio dei simili, allo stesso valore complessivo.
    func test_detectorStageBoundaryDoesNotRegress() {
        let endOfDuplicates = ScanPipelineProgress(
            stage: .analyzingExactDuplicates, stageProgress: AnalysisProgress(processed: 9, total: 9)
        )
        let startOfSimilar = ScanPipelineProgress(
            stage: .analyzingSimilarPhotos, stageProgress: AnalysisProgress(processed: 0, total: 40)
        )
        XCTAssertEqual(endOfDuplicates.fraction, startOfSimilar.fraction, accuracy: 0.0001)
        // FSE-G1: duplicati è ora la 4ª fase (indice 3, residenza fuori dalla barra):
        // la sua fine è 4/7.
        XCTAssertEqual(endOfDuplicates.fraction, 4.0 / stageCount, accuracy: 0.0001)
    }

    // Monotonìa al confine: fine di una fase e inizio della successiva danno lo
    // STESSO valore complessivo → la barra non arretra cambiando fase.
    func test_stageBoundaryDoesNotRegress() {
        let endOfIndexing = ScanPipelineProgress(
            stage: .indexing, stageProgress: AnalysisProgress(processed: 7, total: 7)
        )
        let startOfSizes = ScanPipelineProgress(
            stage: .resolvingSizes, stageProgress: AnalysisProgress(processed: 0, total: 999)
        )
        XCTAssertEqual(endOfIndexing.fraction, startOfSizes.fraction, accuracy: 0.0001)
        XCTAssertEqual(endOfIndexing.fraction, 1.0 / stageCount, accuracy: 0.0001)
    }

    // La frazione è composta dalla frazione REALE della fase, non fabbricata: metà
    // della seconda fase = una fase intera + mezza = 1.5/N (N = numero di fasi).
    func test_fractionComposesRealStageFraction() {
        let progress = ScanPipelineProgress(
            stage: .resolvingSizes, stageProgress: AnalysisProgress(processed: 1, total: 2)
        )
        XCTAssertEqual(progress.fraction, 1.5 / stageCount, accuracy: 0.0001)
    }

    // Un totale nullo per la fase è "completo" (AnalysisProgress lo definisce così):
    // una libreria vuota non incolla la barra a inizio fase.
    func test_emptyStageCountsAsComplete() {
        let progress = ScanPipelineProgress(
            stage: .indexing, stageProgress: AnalysisProgress(processed: 0, total: 0)
        )
        // fase indexing completa → siamo a 1/N.
        XCTAssertEqual(progress.fraction, 1.0 / stageCount, accuracy: 0.0001)
    }
}
