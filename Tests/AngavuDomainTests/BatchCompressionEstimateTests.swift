import XCTest
@testable import AngavuDomain

// B-2a — Stima di BATCH del risparmio. Oracolo puro (gira ovunque).
//
// Invarianti onestà: ogni saving e il totale sono `estimated` (mai esatti); un
// video senza spec è DICHIARATO non stimabile ed escluso dal totale (mai stimato
// con numeri inventati); l'ordine d'input è preservato.

final class BatchCompressionEstimateTests: XCTestCase {

    private func spec(bytes: Int64, seconds: Double, bitrate: Int64) -> VideoSpec {
        VideoSpec(originalBytes: bytes, durationSeconds: seconds, sourceBitrateBitsPerSec: bitrate)
    }

    // Given N video con spec note → il totale = somma dei saving, marcato stima.
    func test_total_isSumOfEstimatedSavings_andAlwaysEstimated() {
        let items = [
            BatchCompressionItem(id: "a", spec: spec(bytes: 200_000_000, seconds: 120, bitrate: 12_000_000)),
            BatchCompressionItem(id: "b", spec: spec(bytes: 100_000_000, seconds: 60, bitrate: 12_000_000))
        ]

        let result = BatchCompressionEstimator.estimate(items: items, preset: .balanced)

        let expectedSum = result.perItem.reduce(Int64(0)) { $0 + $1.saving.bytes }
        XCTAssertEqual(result.total.bytes, expectedSum)
        XCTAssertFalse(result.total.isExact, "il totale non va mai spacciato per esatto")
        for item in result.perItem {
            XCTAssertFalse(item.saving.isExact, "ogni saving è una stima")
        }
        XCTAssertEqual(result.estimableCount, 2)
        XCTAssertTrue(result.unestimableIds.isEmpty)
    }

    // Given un video senza spec → escluso dal totale, dichiarato non stimabile.
    func test_missingSpec_isDeclaredUnestimable_notCountedAsZero() {
        let items = [
            BatchCompressionItem(id: "a", spec: spec(bytes: 200_000_000, seconds: 120, bitrate: 12_000_000)),
            BatchCompressionItem(id: "b", spec: nil),          // non leggibile off-device
            BatchCompressionItem(id: "c", spec: spec(bytes: 100_000_000, seconds: 60, bitrate: 12_000_000))
        ]

        let result = BatchCompressionEstimator.estimate(items: items, preset: .highQuality)

        XCTAssertEqual(result.unestimableIds, ["b"], "l'id senza spec è dichiarato, non stimato")
        XCTAssertEqual(result.perItem.map(\.id), ["a", "c"], "ordine d'input preservato, 'b' escluso")
        let onlyEstimable = BatchCompressionEstimator.estimate(
            items: [items[0], items[2]], preset: .highQuality
        )
        XCTAssertEqual(result.total.bytes, onlyEstimable.total.bytes,
                       "il non-stimabile non aggiunge 0 né altro al totale")
    }

    // Lista vuota → totale stima 0, niente per-item, niente non-stimabili.
    func test_emptyBatch_isZeroEstimatedTotal() {
        let result = BatchCompressionEstimator.estimate(items: [], preset: .balanced)

        XCTAssertTrue(result.perItem.isEmpty)
        XCTAssertTrue(result.unestimableIds.isEmpty)
        XCTAssertFalse(result.total.isExact)
        XCTAssertEqual(result.total.bytes, 0)
    }

    // Tutti senza spec → totale stima 0, tutti dichiarati non stimabili (onestà).
    func test_allUnestimable_totalZeroAndAllDeclared() {
        let items = [
            BatchCompressionItem(id: "x", spec: nil),
            BatchCompressionItem(id: "y", spec: nil)
        ]

        let result = BatchCompressionEstimator.estimate(items: items, preset: .balanced)

        XCTAssertEqual(result.unestimableIds, ["x", "y"])
        XCTAssertTrue(result.perItem.isEmpty)
        XCTAssertEqual(result.total.bytes, 0)
        XCTAssertFalse(result.total.isExact)
    }
}
