import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — «Cosa NON facciamo»: la presentazione PURA dei non-goals è l'oracolo
// della schermata (quali righe, quale icona, quale onestà). La resa SwiftUI resta
// compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class NonGoalsPresentationTests: XCTestCase {

    // Ogni non-goal del contenuto diventa una riga, nello stesso ordine.
    func test_rows_mapEveryNonGoalInOrder() {
        let content = ManifestContent.angavu
        let pres = NonGoalsPresentation(content: content)
        XCTAssertEqual(pres.rows.map(\.id), content.nonGoals.map(\.id))
        XCTAssertEqual(pres.count, content.nonGoals.count)
    }

    // Testo, motivazione e icona non sono mai vuoti: nessuna riga muta.
    func test_rows_haveNonEmptyTextRationaleAndSymbol() {
        let pres = NonGoalsPresentation()
        for row in pres.rows {
            XCTAssertFalse(row.text.isEmpty, "testo vuoto per \(row.id)")
            XCTAssertFalse(row.rationale.isEmpty, "motivazione vuota per \(row.id)")
            XCTAssertFalse(row.symbolName.isEmpty, "icona vuota per \(row.id)")
        }
    }

    // Contenuto canonico: OGNI voce è una rinuncia, mai un claim (AC-100-2).
    func test_canonicalContent_allAreRenunciations() {
        XCTAssertTrue(NonGoalsPresentation(content: .angavu).allAreRenunciations)
    }

    // Contro-prova: se una voce promettesse una capacità, l'invariante cade —
    // l'oracolo non è vacuo.
    func test_capabilityClaim_breaksRenunciationInvariant() {
        let tainted = ManifestContent(
            headline: "x",
            promises: [],
            nonGoals: [
                NonGoal(
                    id: .antivirus,
                    text: "Antivirus completo",
                    rationale: "—",
                    claimsCapability: true
                )
            ]
        )
        XCTAssertFalse(NonGoalsPresentation(content: tainted).allAreRenunciations)
    }

    // Titolo e sottotitolo sono presenti (intro non muta).
    func test_titleAndSubtitle_arePresent() {
        let pres = NonGoalsPresentation()
        XCTAssertFalse(pres.title.isEmpty)
        XCTAssertFalse(pres.subtitle.isEmpty)
    }

    // La mappa d'icona è totale sui casi noti e distinta per categoria.
    func test_symbol_isDistinctPerCategory() {
        let symbols = NonGoalID.allCases.map(NonGoalsPresentation.symbol(for:))
        XCTAssertEqual(symbols.count, NonGoalID.allCases.count)
        XCTAssertEqual(Set(symbols).count, symbols.count, "icone duplicate fra categorie")
    }
}
