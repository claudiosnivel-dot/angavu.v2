import XCTest
@testable import AngavuDomain

// B-2c — Riduttore della coda di compressione. Oracolo puro.
//
// Verifica: progresso determinato X/N; un fallimento per-item NON aborta il batch;
// la cancellazione lascia i residui non processati (dichiarati cancelled) e non
// tocca gli esiti già ottenuti; coda vuota è finita subito; esiti idempotenti.

final class BatchCompressionRunTests: XCTestCase {

    // Coda 3/3 con 1 fallimento al 2°: il batch prosegue → {ok, failed, ok}, 3/3.
    func test_perItemFailure_doesNotAbort_batchCompletes() throws {
        var run = BatchCompressionRun(queue: ["a", "b", "c"])

        // 1° item → success.
        var idx = try XCTUnwrap(run.nextPendingIndex)
        XCTAssertEqual(idx, 0)
        run.record(.succeeded(outputBytes: 10), at: idx)
        XCTAssertEqual(run.progress.processed, 1)

        // 2° item → failed: NON deve fermare la coda.
        idx = try XCTUnwrap(run.nextPendingIndex)
        XCTAssertEqual(idx, 1)
        run.record(.failed(reason: "export non riuscito"), at: idx)

        // 3° item → success.
        idx = try XCTUnwrap(run.nextPendingIndex)
        XCTAssertEqual(idx, 2, "dopo un fallimento la coda avanza al prossimo pending")
        run.record(.succeeded(outputBytes: 30), at: idx)

        XCTAssertNil(run.nextPendingIndex)
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(run.succeededCount, 2)
        XCTAssertEqual(run.failedCount, 1)
        XCTAssertEqual(run.progress.processed, 3)
        XCTAssertEqual(run.progress.total, 3)
        XCTAssertEqual(run.totalOutputBytes, 40, "solo i success reali sommano l'output")
    }

    // Cancel dopo il 1°: i residui non sono processati (cancelled), il 1° resta.
    func test_cancel_leavesRemainderUnprocessed_keepsDoneOutcomes() {
        var run = BatchCompressionRun(queue: ["a", "b", "c"])

        run.record(.succeeded(outputBytes: 10), at: 0)
        run.cancel()

        XCTAssertTrue(run.isCancelled)
        XCTAssertNil(run.nextPendingIndex, "cancellata: nessun altro item da processare")
        XCTAssertEqual(run.succeededCount, 1, "l'esito già ottenuto resta")
        XCTAssertEqual(run.cancelledCount, 2, "i residui sono dichiarati non processati")
        XCTAssertEqual(run.progress.processed, 3, "progresso completo: tutti hanno un esito")
        XCTAssertTrue(run.isFinished)
    }

    // Coda vuota: finita subito, progresso 0/0.
    func test_emptyQueue_isFinishedImmediately() {
        let run = BatchCompressionRun(queue: [])

        XCTAssertTrue(run.isFinished)
        XCTAssertNil(run.nextPendingIndex)
        XCTAssertEqual(run.total, 0)
        XCTAssertEqual(run.completedCount, 0)
    }

    // Un esito non si sovrascrive (idempotenza) né si registra fuori range.
    func test_record_isIdempotent_andBoundsChecked() {
        var run = BatchCompressionRun(queue: ["a"])

        run.record(.succeeded(outputBytes: 5), at: 0)
        run.record(.failed(reason: "tardivo"), at: 0)   // ignorato: già con esito
        run.record(.succeeded(outputBytes: 99), at: 7)  // ignorato: fuori range

        XCTAssertEqual(run.succeededCount, 1)
        XCTAssertEqual(run.failedCount, 0)
        XCTAssertEqual(run.totalOutputBytes, 5)
    }

    // Progresso determinato monotòno lungo l'avanzamento.
    func test_progress_isDeterminateAndMonotonic() {
        var run = BatchCompressionRun(queue: ["a", "b"])

        XCTAssertEqual(run.progress.processed, 0)
        XCTAssertEqual(run.progress.total, 2)
        run.record(.succeeded(outputBytes: 1), at: 0)
        XCTAssertEqual(run.progress.processed, 1)
        run.record(.succeeded(outputBytes: 1), at: 1)
        XCTAssertEqual(run.progress.processed, 2)
        XCTAssertEqual(run.progress.fraction, 1.0, accuracy: 0.0001)
    }
}
