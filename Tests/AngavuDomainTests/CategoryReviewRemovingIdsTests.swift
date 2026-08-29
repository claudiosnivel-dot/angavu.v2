import XCTest
import AngavuDomain

// FSE-J2 (AC-FSE-J2-1) — Oracolo di `CategoryReview.removing(ids:)` (ora Domain puro,
// spostato da Features): togliere id da keep+removable, il resto resta, ordine stabile,
// no-op su insieme vuoto. È la potatura riusata sia dall'eliminazione reale (J1) sia
// dall'invalidazione chirurgica della cache (J2).

final class CategoryReviewRemovingIdsTests: XCTestCase {

    func test_removing_dropsIdsFromBothKeepAndRemovable_keepsOrder() {
        let review = CategoryReview(keepIds: ["k1", "k2"], removableIds: ["r1", "r2", "r3"])
        let pruned = review.removing(ids: ["k1", "r2"])
        XCTAssertEqual(pruned.keepIds, ["k2"], "l'id keep eliminato sparisce, il resto resta")
        XCTAssertEqual(pruned.removableIds, ["r1", "r3"], "ordine stabile del resto")
    }

    func test_removing_emptySet_isNoOp() {
        let review = CategoryReview(keepIds: ["k1"], removableIds: ["r1", "r2"])
        XCTAssertEqual(review.removing(ids: []), review)
    }

    func test_removing_idsNotPresent_leavesReviewUnchanged() {
        let review = CategoryReview(keepIds: ["k1"], removableIds: ["r1"])
        XCTAssertEqual(review.removing(ids: ["zzz"]), review)
    }

    func test_removing_allIds_yieldsEmptyReview() {
        let review = CategoryReview(keepIds: ["k1"], removableIds: ["r1", "r2"])
        let pruned = review.removing(ids: ["k1", "r1", "r2"])
        XCTAssertTrue(pruned.keepIds.isEmpty)
        XCTAssertTrue(pruned.removableIds.isEmpty)
    }

    func test_removing_dropsOnlyMatchingIds_partialOverlap() {
        // L'insieme da togliere può eccedere quello presente: si toglie solo l'intersezione.
        let review = CategoryReview(keepIds: ["k1"], removableIds: ["r1", "r2"])
        let pruned = review.removing(ids: ["r1", "ghost"])
        XCTAssertEqual(pruned.keepIds, ["k1"])
        XCTAssertEqual(pruned.removableIds, ["r2"])
    }
}
