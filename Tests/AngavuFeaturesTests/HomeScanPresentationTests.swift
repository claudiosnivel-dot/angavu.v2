import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — Home: la presentazione PURA dello stato di scansione è l'oracolo
// della logica di Home (quali controlli, quali numeri, quale onestà). La resa
// SwiftUI resta compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class HomeScanPresentationTests: XCTestCase {

    // idle → invito ad analizzare, pulsante primario, niente annulla/progresso.
    func test_idle_offersPrimaryScan() {
        let pres = HomeScanPresentation(state: .idle)
        XCTAssertEqual(pres.kind, .idle)
        XCTAssertTrue(pres.showsPrimaryAction)
        XCTAssertEqual(pres.primaryActionTitle, "Analizza la libreria")
        XCTAssertFalse(pres.canCancel)
        XCTAssertNil(pres.progress)
        XCTAssertFalse(pres.offersOpenSettings)
    }

    // requestingPermission → in corso ma NON annullabile e senza progresso noto.
    func test_requestingPermission_isWorkingNotCancellable() {
        let pres = HomeScanPresentation(state: .requestingPermission)
        XCTAssertEqual(pres.kind, .working)
        XCTAssertFalse(pres.canCancel)
        XCTAssertFalse(pres.showsPrimaryAction)
        XCTAssertNil(pres.progress)
    }

    // scanning → in corso, annullabile (stop cooperativo), progresso esposto.
    func test_scanning_isCancellableWithProgress() {
        let progress = AnalysisProgress(processed: 3, total: 10)
        let pres = HomeScanPresentation(state: .scanning(progress))
        XCTAssertEqual(pres.kind, .working)
        XCTAssertTrue(pres.canCancel)
        XCTAssertFalse(pres.showsPrimaryAction)
        XCTAssertEqual(pres.progress, progress)
    }

    // completed accesso pieno → recap con conteggio, NON parziale, rianalizzabile.
    func test_completedFull_showsHonestFullRecap() {
        let pres = HomeScanPresentation(state: .completed(indexed: 42, partialCount: false))
        XCTAssertEqual(pres.kind, .completed)
        XCTAssertEqual(pres.indexedCount, 42)
        XCTAssertFalse(pres.isPartialResult)
        XCTAssertTrue(pres.showsPrimaryAction)
        XCTAssertEqual(pres.primaryActionTitle, "Rianalizza")
        XCTAssertNil(pres.progress)
    }

    // completed accesso limited → il conteggio è dichiarato PARZIALE, mai totale.
    func test_completedLimited_marksPartial() {
        let pres = HomeScanPresentation(state: .completed(indexed: 7, partialCount: true))
        XCTAssertEqual(pres.indexedCount, 7)
        XCTAssertTrue(pres.isPartialResult)
        XCTAssertNotNil(pres.detail)
        XCTAssertTrue(pres.detail?.contains("parziale") ?? false)
    }

    // cancelled → annullata, riprovabile, nessuna modifica, progresso nel dettaglio.
    func test_cancelled_isRetryableAndReportsNoChange() {
        let progress = AnalysisProgress(processed: 4, total: 9)
        let pres = HomeScanPresentation(state: .cancelled(progress))
        XCTAssertEqual(pres.kind, .cancelled)
        XCTAssertTrue(pres.showsPrimaryAction)
        XCTAssertEqual(pres.primaryActionTitle, "Riprova")
        XCTAssertFalse(pres.canCancel)
    }

    // failed per accesso negato → offre "Apri Impostazioni".
    func test_failedAccessDenied_offersOpenSettings() {
        let pres = HomeScanPresentation(state: .failed(ScanViewModel.accessDeniedMessage))
        XCTAssertEqual(pres.kind, .failed)
        XCTAssertTrue(pres.offersOpenSettings)
        XCTAssertTrue(pres.showsPrimaryAction)
        XCTAssertEqual(pres.primaryActionTitle, "Riprova")
    }

    // failed generico → NIENTE scorciatoia Impostazioni (non è un problema di permessi).
    func test_failedGeneric_doesNotOfferSettings() {
        let pres = HomeScanPresentation(state: .failed("Errore di lettura dell'indice."))
        XCTAssertEqual(pres.kind, .failed)
        XCTAssertFalse(pres.offersOpenSettings)
        XCTAssertEqual(pres.detail, "Errore di lettura dell'indice.")
    }
}
