import XCTest
import AngavuDomain
@testable import AngavuFeatures

// E-3 — La decisione "quale esito → quale schermata (festa vs onesto)" è il layer
// PURO ed è l'oracolo di onestà: mai coriandoli su un mezzo successo. Le animazioni
// (coriandoli) restano View-level, gated su Reduce Motion (L-COL-006).

final class ScanSuccessPresentationTests: XCTestCase {

    // Successo pieno → FESTA: coriandoli, conteggio reale, porta alla dashboard.
    func test_completedFull_celebratesWithRealCount() {
        let result = ScanSuccessPresentation.make(state: .completed(indexed: 2503, partialCount: false))
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertEqual(unwrapped?.style, .celebration)
        XCTAssertEqual(unwrapped?.showsConfetti, true)
        XCTAssertEqual(unwrapped?.indexedCount, 2503)
        XCTAssertFalse(unwrapped?.isPartialResult ?? true)
        XCTAssertEqual(unwrapped?.primaryActionTitle, "È ora di fare pulizia!")
        XCTAssertEqual(unwrapped?.leadsToDashboard, true)
        XCTAssertTrue(unwrapped?.message.contains("2503") ?? false)
    }

    // Accesso limitato → NIENTE festa: ramo onesto, conteggio dichiarato parziale,
    // invito all'accesso completo. La dashboard resta raggiungibile.
    func test_completedLimited_honestNoConfettiMarksPartial() {
        let result = ScanSuccessPresentation.make(state: .completed(indexed: 7, partialCount: true))
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertEqual(unwrapped?.style, .honest)
        XCTAssertEqual(unwrapped?.showsConfetti, false)
        XCTAssertEqual(unwrapped?.isPartialResult, true)
        XCTAssertTrue(unwrapped?.message.contains("parziale") ?? false)
        XCTAssertEqual(unwrapped?.offersOpenSettings, true)
        XCTAssertEqual(unwrapped?.leadsToDashboard, true)
    }

    // Fallimento per accesso negato → ramo onesto, "Apri Impostazioni", niente festa,
    // NON porta alla dashboard (invita a riprovare).
    func test_failedAccessDenied_honestOffersSettingsRetry() {
        let result = ScanSuccessPresentation.make(state: .failed(ScanViewModel.accessDeniedMessage))
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertEqual(unwrapped?.style, .honest)
        XCTAssertEqual(unwrapped?.showsConfetti, false)
        XCTAssertEqual(unwrapped?.offersOpenSettings, true)
        XCTAssertEqual(unwrapped?.primaryActionTitle, "Riprova")
        XCTAssertEqual(unwrapped?.leadsToDashboard, false)
    }

    // Fallimento generico → ramo onesto SENZA scorciatoia Impostazioni (non è permessi).
    func test_failedGeneric_honestNoSettings() {
        let result = ScanSuccessPresentation.make(state: .failed("Errore di lettura dell'indice."))
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertEqual(unwrapped?.style, .honest)
        XCTAssertEqual(unwrapped?.offersOpenSettings, false)
        XCTAssertEqual(unwrapped?.message, "Errore di lettura dell'indice.")
    }

    // Stati NON terminali → nessuna schermata di risultato (mostrano il flusso).
    func test_nonTerminalStates_produceNoResultScreen() {
        XCTAssertNil(ScanSuccessPresentation.make(state: .idle))
        XCTAssertNil(ScanSuccessPresentation.make(state: .requestingPermission))
        XCTAssertNil(ScanSuccessPresentation.make(state: .scanning(AnalysisProgress(processed: 1, total: 4))))
        XCTAssertNil(ScanSuccessPresentation.make(state: .cancelled(AnalysisProgress(processed: 2, total: 4))))
    }
}
