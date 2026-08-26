import XCTest
import AngavuDomain
@testable import AngavuFeatures

// B-2d — Presentazione pura del batch: riepilogo selezione + riepilogo coda.
//
// Onestà: il totale è la somma dei saving stimati dei SOLI selezionati stimabili;
// i selezionati senza spec sono contati a parte (mai sommati come 0); il progresso
// del run è determinato; il cap della stima è dichiarato quando presente.

final class BatchCompressionPresentationTests: XCTestCase {

    private func spec(bytes: Int64, seconds: Double, bitrate: Int64) -> VideoSpec {
        VideoSpec(originalBytes: bytes, durationSeconds: seconds, sourceBitrateBitsPerSec: bitrate)
    }

    // Il totale del riepilogo somma i saving dei SOLI selezionati stimabili.
    func test_summary_totalsOnlySelectedEstimables() throws {
        let items = [
            BatchCompressionItem(id: "a", spec: spec(bytes: 200_000_000, seconds: 120, bitrate: 12_000_000)),
            BatchCompressionItem(id: "b", spec: spec(bytes: 100_000_000, seconds: 60, bitrate: 12_000_000)),
            BatchCompressionItem(id: "c", spec: nil)   // non stimabile
        ]
        let estimate = BatchCompressionEstimator.estimate(items: items, preset: .balanced)

        var selection = BatchCompressionSelection(available: ["a", "b", "c"])
        selection.toggle("a")
        selection.toggle("c")   // selezionato ma non stimabile

        let summary = BatchCompressionSummary(estimate: estimate, selection: selection)

        let savingA = try XCTUnwrap(estimate.perItem.first { $0.id == "a" }).saving.bytes
        XCTAssertEqual(summary.selectedEstimatedSavingBytes, savingA,
                       "solo 'a' è selezionato E stimabile; 'b' non è selezionato, 'c' non stimabile")
        XCTAssertEqual(summary.selectedUnestimableCount, 1, "'c' selezionato senza spec è dichiarato")
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertTrue(summary.canStart)
    }

    // Selezione vuota → totale 0, avvio negato (opt-in).
    func test_summary_emptySelection_cannotStart() {
        let estimate = BatchCompressionEstimator.estimate(
            items: [BatchCompressionItem(id: "a", spec: spec(bytes: 100, seconds: 10, bitrate: 1_000_000))],
            preset: .balanced
        )
        let selection = BatchCompressionSelection(available: ["a"])

        let summary = BatchCompressionSummary(estimate: estimate, selection: selection)

        XCTAssertEqual(summary.selectedCount, 0)
        XCTAssertFalse(summary.canStart)
        XCTAssertEqual(summary.selectedEstimatedSavingBytes, 0)
    }

    // Run in corso → phase .running, progresso determinato X/N.
    func test_runSummary_running_isDeterminate() {
        var run = BatchCompressionRun(queue: ["a", "b", "c"])
        run.record(.succeeded(outputBytes: 50), at: 0)

        let summary = BatchCompressionRunSummary(run: run)

        XCTAssertEqual(summary.phase, .running)
        XCTAssertEqual(summary.processed, 1)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.fraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    // Run concluso con esiti misti → conteggi e output reale aggregati.
    func test_runSummary_done_aggregatesOutcomes() {
        var run = BatchCompressionRun(queue: ["a", "b"])
        run.record(.succeeded(outputBytes: 40), at: 0)
        run.record(.failed(reason: "x"), at: 1)

        let summary = BatchCompressionRunSummary(run: run)

        XCTAssertEqual(summary.phase, .done)
        XCTAssertEqual(summary.succeeded, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.cancelled, 0)
        XCTAssertEqual(summary.totalOutputBytes, 40)
        XCTAssertEqual(summary.fraction, 1.0, accuracy: 0.0001)
    }

    // Il cap della stima è dichiarato quando i candidati superano i mostrati.
    func test_capNotice_declaredWhenTruncated_nilOtherwise() throws {
        XCTAssertNil(BatchCompressionCopy.estimateCapNotice(shown: 100, totalCandidates: 100))
        XCTAssertNil(BatchCompressionCopy.estimateCapNotice(shown: 100, totalCandidates: 40))
        let notice = try XCTUnwrap(BatchCompressionCopy.estimateCapNotice(shown: 100, totalCandidates: 2503))
        XCTAssertTrue(notice.contains("100"))
        XCTAssertTrue(notice.contains("2503"))
    }
}
