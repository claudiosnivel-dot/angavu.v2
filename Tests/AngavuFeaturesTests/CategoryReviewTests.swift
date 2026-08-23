import XCTest
import AngavuDomain
@testable import AngavuFeatures

// T-113 — AC-113-1 / AC-113-2. Review di categoria: proposte → keep/removable,
// eliminazione instradata SEMPRE al DeletionFlow (rete di sicurezza), mai sui keep.

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

private func video(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .video, pixelSize: PixelSize(width: 100, height: 100), creationDate: nil, subtypes: [])
}

private func sized(_ id: String, _ bytes: Int64) -> SizedAsset {
    SizedAsset(asset: photo(id), size: .exact(bytes: bytes))
}

private func candidate(_ id: String) -> SimilarityCandidate {
    SimilarityCandidate(asset: photo(id), dHash: nil)
}

final class CategoryReviewTests: XCTestCase {

    // AC-113-1: eliminando i removable, il DeletionFlow arriva a confirmed
    // esattamente sull'insieme removable, mai sui keep.
    func test_deletingRemovableConfirmsExactlyThatSetNeverKeep() {
        let review = CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"])
        let vm = CategoryReviewViewModel(review: review)

        let ok = vm.requestDeletionOfAllRemovable()

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.flow.state, .confirmed(assets: ["R1", "R2"]))
        XCTAssertFalse(vm.flow.pendingAssets.contains("K1"), "un keep non deve mai finire nell'eliminazione")
    }

    // AC-113-2: nessuna selezione ⇒ azione rifiutata, nessuna anteprima vuota.
    func test_emptySelectionIsRejected() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1"]))

        XCTAssertFalse(vm.requestDeletion(of: []))
        XCTAssertEqual(vm.flow.state, .idle, "nessun preview aperto su selezione vuota")
    }

    // Selezione di soli keep ⇒ rifiutata (nessun removable eleggibile).
    func test_selectionOfOnlyKeepIsRejected() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1"]))

        XCTAssertFalse(vm.requestDeletion(of: ["K1"]))
        XCTAssertEqual(vm.flow.state, .idle)
    }

    // Selezione mista: i keep sono filtrati, solo i removable entrano nel confirmed.
    func test_keepIdsAreFilteredFromMixedSelection() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]))

        XCTAssertTrue(vm.requestDeletion(of: ["K1", "R1"]))
        XCTAssertEqual(vm.flow.state, .confirmed(assets: ["R1"]))
    }

    // Righe presentabili: prima i keep, poi i removable.
    func test_rowsExposeKeepThenRemovable() {
        let review = CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"])
        XCTAssertEqual(review.rows, [
            CategoryReviewRow(id: "K1", disposition: .keep),
            CategoryReviewRow(id: "R1", disposition: .removable),
            CategoryReviewRow(id: "R2", disposition: .removable)
        ])
    }

    // MARK: - Normalizzazione dalle proposte dei rilevatori

    func test_normalizesKeepOneProposal() {
        let proposal = KeepOneProposal(keep: sized("A", 10), removable: [sized("B", 10), sized("C", 10)])
        let review = CategoryReview.from(keepOne: proposal)
        XCTAssertEqual(review.keepIds, ["A"])
        XCTAssertEqual(review.removableIds, ["B", "C"])
    }

    func test_normalizesSimilarDeletionProposal() {
        let proposal = DeletionProposal(keep: candidate("A"), removable: [candidate("B")])
        let review = CategoryReview.from(similar: proposal)
        XCTAssertEqual(review.keepIds, ["A"])
        XCTAssertEqual(review.removableIds, ["B"])
    }

    func test_normalizesBulkProposalNoKeep() {
        let proposal = BulkDeletionProposal(removable: [video("V1"), video("V2")])
        let review = CategoryReview.from(bulk: proposal)
        XCTAssertTrue(review.keepIds.isEmpty)
        XCTAssertEqual(review.removableIds, ["V1", "V2"])
    }

    func test_normalizesBlurryNoKeep() {
        let review = CategoryReview.fromBlurry([photo("P1"), photo("P2")])
        XCTAssertTrue(review.keepIds.isEmpty)
        XCTAssertEqual(review.removableIds, ["P1", "P2"])
    }
}
