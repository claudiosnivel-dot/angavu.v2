import XCTest
@testable import AngavuDomain

// B-2b — Selezione del sottoinsieme da comprimere. Oracolo puro.
//
// Invarianti: default opt-in (nulla selezionato → canStart falso); toggle
// idempotente e limitato all'universo; all/none coprono esattamente i candidati;
// l'ordine d'avvio segue l'universo (deterministico), non l'ordine del Set.

final class BatchCompressionSelectionTests: XCTestCase {

    private let universe = ["a", "b", "c"]

    // Default onesto: nulla preselezionato, l'avvio è rifiutato.
    func test_default_isEmpty_andCannotStart() {
        let sel = BatchCompressionSelection(available: universe)

        XCTAssertTrue(sel.selected.isEmpty)
        XCTAssertFalse(sel.canStart, "opt-in: senza selezione la compressione non parte")
        XCTAssertEqual(sel.selectedCount, 0)
    }

    // Toggle seleziona/deseleziona; idempotente su doppia inversione.
    func test_toggle_selectsAndDeselects() {
        var sel = BatchCompressionSelection(available: universe)

        sel.toggle("b")
        XCTAssertEqual(sel.selected, ["b"])
        XCTAssertTrue(sel.canStart)

        sel.toggle("b")
        XCTAssertTrue(sel.selected.isEmpty, "il secondo toggle deseleziona")
        XCTAssertFalse(sel.canStart)
    }

    // Un id fuori dall'universo non è selezionabile.
    func test_toggle_ignoresUnknownId() {
        var sel = BatchCompressionSelection(available: universe)

        sel.toggle("zzz")
        XCTAssertTrue(sel.selected.isEmpty, "non si seleziona ciò che non è un candidato")
    }

    // Seleziona tutto / niente coprono esattamente i candidati.
    func test_selectAll_thenNone() {
        var sel = BatchCompressionSelection(available: universe)

        sel.selectAll()
        XCTAssertEqual(sel.selected, Set(universe))
        XCTAssertEqual(sel.selectedCount, 3)

        sel.selectNone()
        XCTAssertTrue(sel.selected.isEmpty)
    }

    // L'ordine d'avvio segue l'universo, non l'ordine arbitrario del Set.
    func test_selectedInOrder_followsUniverseOrder() {
        var sel = BatchCompressionSelection(available: universe)

        sel.toggle("c")
        sel.toggle("a")
        XCTAssertEqual(sel.selectedInOrder, ["a", "c"], "ordine dell'universo, deterministico")
    }

    // Init difensivo: id selezionati fuori universo sono scartati.
    func test_init_dropsSelectedOutsideUniverse() {
        let sel = BatchCompressionSelection(available: universe, selected: ["a", "ghost"])

        XCTAssertEqual(sel.selected, ["a"])
    }
}
