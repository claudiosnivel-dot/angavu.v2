import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — Onboarding-manifesto: la presentazione PURA è l'oracolo della voce
// d'apertura (headline, promesse, icone, onestà on-device). La resa SwiftUI resta
// compilata-ma-non-testata (L-COL-006); qui si prova la mappa.

final class OnboardingManifestoPresentationTests: XCTestCase {

    // Ogni promessa del contenuto diventa una riga, nello stesso ordine.
    func test_promises_mapEveryPromiseInOrder() {
        let content = ManifestContent.angavu
        let pres = OnboardingManifestoPresentation(content: content)
        XCTAssertEqual(pres.promises.map(\.id), content.promises.map(\.id))
    }

    // Testo e icona di ogni promessa non sono mai vuoti.
    func test_promises_haveNonEmptyTextAndSymbol() {
        let pres = OnboardingManifestoPresentation()
        for row in pres.promises {
            XCTAssertFalse(row.text.isEmpty, "testo vuoto per \(row.id)")
            XCTAssertFalse(row.symbolName.isEmpty, "icona vuota per \(row.id)")
        }
    }

    // La headline è quella del contenuto (nessun testo fabbricato).
    func test_headline_comesFromContent() {
        let content = ManifestContent.angavu
        XCTAssertEqual(OnboardingManifestoPresentation(content: content).headline, content.headline)
    }

    // Wordmark ed etichette dei controlli sono presenti.
    func test_wordmarkAndLabels_arePresent() {
        let pres = OnboardingManifestoPresentation()
        XCTAssertEqual(pres.wordmark, "Angavu")
        XCTAssertFalse(pres.continueTitle.isEmpty)
        XCTAssertFalse(pres.nonGoalsLinkTitle.isEmpty)
    }

    // Contenuto canonico: OGNI promessa è mantenibile on-device (AC-100-2).
    func test_canonicalContent_allPromisesOnDevice() {
        XCTAssertTrue(OnboardingManifestoPresentation(content: .angavu).allPromisesOnDevice)
    }

    // Contro-prova: una promessa non-on-device rompe l'invariante — oracolo non vacuo.
    func test_offDevicePromise_breaksOnDeviceInvariant() {
        let tainted = ManifestContent(
            headline: "x",
            promises: [
                ManifestPromise(id: .realNumbers, text: "Sync cloud", achievableOnDevice: false)
            ],
            nonGoals: []
        )
        XCTAssertFalse(OnboardingManifestoPresentation(content: tainted).allPromisesOnDevice)
    }

    // La mappa d'icona è totale sui casi noti e distinta per promessa.
    func test_symbol_isDistinctPerPromise() {
        let symbols = ManifestPromiseID.allCases.map(OnboardingManifestoPresentation.symbol(for:))
        XCTAssertEqual(Set(symbols).count, symbols.count, "icone duplicate fra promesse")
    }
}
