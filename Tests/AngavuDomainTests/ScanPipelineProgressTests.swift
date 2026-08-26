import XCTest
import AngavuDomain

// Oracolo del progresso UNIFICATO della scansione: la barra unica non arretra mai
// passando di fase e la frazione è composta dalle frazioni REALI per-fase (mai
// fabbricata). Tre fasi equipesate.

final class ScanPipelineProgressTests: XCTestCase {

    private let stageCount = Double(ScanPipelineProgress.Stage.allCases.count)

    // Inizio assoluto: prima fase a 0 → frazione complessiva 0.
    func test_startOfFirstStageIsZero() {
        let progress = ScanPipelineProgress(
            stage: .indexing, stageProgress: AnalysisProgress(processed: 0, total: 10)
        )
        XCTAssertEqual(progress.fraction, 0.0, accuracy: 0.0001)
    }

    // Fine assoluta: ultima fase completa → frazione complessiva 1.
    func test_endOfLastStageIsOne() {
        let progress = ScanPipelineProgress(
            stage: .measuringDeviceSpace, stageProgress: AnalysisProgress(processed: 10, total: 10)
        )
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
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
