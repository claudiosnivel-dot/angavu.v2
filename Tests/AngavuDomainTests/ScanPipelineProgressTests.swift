import XCTest
import AngavuDomain

// Oracolo del progresso UNIFICATO della scansione: la barra unica non arretra mai
// passando di fase e la frazione è composta dalle frazioni REALI per-fase (mai
// fabbricata). FSE-F1: OTTO fasi equipesate — le tre dei numeri veri (indice → byte →
// residenza) e le cinque dei RILEVATORI di categoria (screenshot, duplicati, simili,
// sfocate, grandi/vecchi), calcolati nella stessa passata.

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

    // La fase dei numeri (residenza) NON è più la fine: restano le cinque fasi dei
    // rilevatori. Fine della residenza = 3/8, non 1 (nessuna barra "finita" prematura).
    func test_measuringDeviceSpaceIsNotTheEnd() {
        let progress = ScanPipelineProgress(
            stage: .measuringDeviceSpace, stageProgress: AnalysisProgress(processed: 10, total: 10)
        )
        XCTAssertEqual(progress.fraction, 3.0 / stageCount, accuracy: 0.0001)
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
        // Duplicati è la 5ª fase (indice 4): la sua fine è 5/8.
        XCTAssertEqual(endOfDuplicates.fraction, 5.0 / stageCount, accuracy: 0.0001)
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
    // della seconda fase (di tre) = una fase intera + mezza = 1.5/3.
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
        // fase indexing completa → siamo a 1/3.
        XCTAssertEqual(progress.fraction, 1.0 / stageCount, accuracy: 0.0001)
    }
}
