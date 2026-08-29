import XCTest
import AngavuData
import AngavuDomain
@testable import AngavuFeatures

// FSE-J1 — Seam test (Livello A, harness FSE-J0 convenzione 2): prova che la conferma
// dell'eliminazione INVOCA DAVVERO il deleter iniettato, con ESATTAMENTE gli id selezionati
// (mai i keep), e aggiorna la review solo sull'esito reale. Becca il bug del censimento C1:
// prima `confirmDeletion()` faceva solo avanzare il gate → nessuna `delete(...)` reale.

/// Spia riusabile conforme al port: registra ogni batch di id passato e restituisce un
/// esito configurabile. Sta al posto dell'adapter PhotoKit reale.
private final class SpyDeleter: AssetDeleting {
    private(set) var deletedBatches: [[String]] = []
    var result: BatchDeletionResult = .success
    func delete(ids: [String]) async -> BatchDeletionResult {
        deletedBatches.append(ids)
        return result
    }
}

final class CategoryDeletionWiringTests: XCTestCase {

    private func makeVM(_ deleter: SpyDeleter) -> CategoryReviewViewModel {
        // K1 è un keep (mai eliminabile); R1/R2 sono removable (preselezionati via policy).
        CategoryReviewViewModel(
            review: CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]),
            deleter: deleter
        )
    }

    // AC-FSE-J1-1 (success): il deleter è invocato UNA volta con esattamente i removable
    // selezionati (mai il keep); su success gli id spariscono dalla review e dalla selezione.
    func test_confirmAndDelete_invokesDeleterWithSelectedIds_andRemovesThemOnSuccess() async {
        let spy = SpyDeleter()
        spy.result = .success
        let vm = makeVM(spy)

        XCTAssertTrue(vm.presentDeletionPreviewForSelection(), "l'anteprima deve aprirsi sui selezionati")
        let result = await vm.confirmAndDelete()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(spy.deletedBatches, [["R1", "R2"]],
                       "il deleter deve essere invocato con ESATTAMENTE i removable selezionati, mai i keep")
        XCTAssertEqual(vm.review.removableIds, [], "su success i removable eliminati spariscono dalla review")
        XCTAssertEqual(vm.review.keepIds, ["K1"], "i keep restano (non erano da eliminare)")
        XCTAssertTrue(vm.selection.isEmpty, "gli id eliminati escono dalla selezione")
    }

    // AC-FSE-J1-1 (failed): il deleter è invocato, ma su failed la review resta INVARIATA
    // (mai un falso successo) e l'esito riporta il motivo.
    func test_confirmAndDelete_leavesReviewUnchangedOnFailure() async {
        let spy = SpyDeleter()
        spy.result = .failed(reason: "errore di sistema")
        let vm = makeVM(spy)

        _ = vm.presentDeletionPreviewForSelection()
        let result = await vm.confirmAndDelete()

        XCTAssertEqual(result, .failed(reason: "errore di sistema"))
        XCTAssertEqual(spy.deletedBatches, [["R1", "R2"]], "il deleter è comunque invocato")
        XCTAssertEqual(vm.review.removableIds, ["R1", "R2"], "su failed nulla è tolto dalla review")
    }

    // AC-FSE-J1-1 (cancelled): utente annulla l'alert di sistema → review invariata.
    func test_confirmAndDelete_leavesReviewUnchangedOnCancel() async {
        let spy = SpyDeleter()
        spy.result = .cancelled
        let vm = makeVM(spy)

        _ = vm.presentDeletionPreviewForSelection()
        let result = await vm.confirmAndDelete()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(vm.review.removableIds, ["R1", "R2"], "su cancelled nulla è tolto dalla review")
    }

    // I keep non finiscono MAI tra gli id eliminati, anche se deselezioni un removable.
    func test_confirmAndDelete_neverDeletesKeepIds() async {
        let spy = SpyDeleter()
        let vm = makeVM(spy)
        vm.toggleSelection("R1") // deseleziona R1 → resta solo R2

        _ = vm.presentDeletionPreviewForSelection()
        _ = await vm.confirmAndDelete()

        XCTAssertEqual(spy.deletedBatches, [["R2"]], "solo il removable ancora selezionato, mai un keep")
        XCTAssertFalse(spy.deletedBatches.flatMap { $0 }.contains("K1"))
    }

    // Il default null-object NON finge un successo: se il deleter non è cablato, l'esito è
    // failed (la View mostra un errore onesto invece di dichiarare "eliminato").
    func test_defaultNoAssetDeleter_reportsFailureNotFakeSuccess() async {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: [], removableIds: ["R1"]))
        _ = vm.presentDeletionPreviewForSelection()
        let result = await vm.confirmAndDelete()
        if case .failed = result { /* atteso */ } else {
            XCTFail("il null-object deve riportare failed, mai success")
        }
        XCTAssertEqual(vm.review.removableIds, ["R1"], "senza deleter reale nulla è tolto")
    }
}
