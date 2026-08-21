import XCTest
@testable import AngavuDomain

/// Oracolo logico di T-004 (AC-004-1/2/3). Domain puro: gira senza device.
final class CancellableAnalysisTests: XCTestCase {

    /// Analisi che conta gli elementi processati, un item per blocco.
    private func counter(chunkSize: Int = 1) -> ChunkedAnalysis<Int, [Int]> {
        ChunkedAnalysis(chunkSize: chunkSize, initial: [Int]()) { acc, item in
            acc + [item]
        }
    }

    // AC-004-1: cancel dopo il primo blocco → esito cancelled entro il blocco
    // successivo, elementi restanti NON processati.
    func testCancelAfterFirstChunkStopsBeforeRemaining() {
        let token = CancellationToken()
        var progressUpdates: [AnalysisProgress] = []
        let analysis = counter(chunkSize: 1)

        let outcome = analysis.run(over: [10, 20, 30, 40], cancellation: token) { progress in
            progressUpdates.append(progress)
            // Dopo aver processato il primo elemento, richiedi la cancellazione.
            if progress.processed == 1 {
                token.cancel()
            }
        }

        switch outcome {
        case .cancelled(let at):
            // Solo il primo blocco è stato processato: 1 su 4.
            XCTAssertEqual(at.processed, 1)
            XCTAssertEqual(at.total, 4)
            XCTAssertFalse(at.isComplete)
        default:
            XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
    }

    // AC-004-2: progresso monotòno non decrescente; raggiunge il totale SOLO a
    // esito completed.
    func testProgressMonotonicAndReachesTotalOnlyWhenCompleted() {
        let token = CancellationToken()
        var seen: [Int] = []
        let analysis = counter(chunkSize: 2)

        let outcome = analysis.run(over: Array(1...6), cancellation: token) { progress in
            seen.append(progress.processed)
        }

        // Monotòno non decrescente.
        XCTAssertEqual(seen, seen.sorted())
        for (prev, next) in zip(seen, seen.dropFirst()) {
            XCTAssertLessThanOrEqual(prev, next)
        }

        // Completed con accumulatore pieno e progresso finale == totale.
        guard case .completed(let result) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(result, Array(1...6))
        XCTAssertEqual(seen.last, 6)
    }

    // Il totale non deve MAI comparire su un esito cancelled.
    func testCancelledNeverReachesTotal() {
        let token = CancellationToken()
        let analysis = counter(chunkSize: 1)
        token.cancel() // cancellato prima ancora di iniziare

        let outcome = analysis.run(over: [1, 2, 3], cancellation: token) { _ in }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
        XCTAssertEqual(at.processed, 0)
        XCTAssertFalse(at.isComplete)
    }

    // AC-004-3: un blocco che solleva errore → esito failed(reason) visibile,
    // con il progresso raggiunto (mai 0% bloccato all'infinito).
    func testFailingStepYieldsExplicitFailureWithProgress() {
        let token = CancellationToken()
        // Fallisce al terzo elemento.
        let analysis = ChunkedAnalysis<Int, Int>(chunkSize: 10, initial: 0) { acc, item in
            if item == 3 { throw AnalysisFailure("boom su \(item)") }
            return acc + item
        }

        let outcome = analysis.run(over: [1, 2, 3, 4], cancellation: token) { _ in }

        guard case .failed(let reason, let at) = outcome else {
            return XCTFail("atteso .failed, ottenuto \(outcome)")
        }
        XCTAssertEqual(reason, AnalysisFailure("boom su 3"))
        // Due elementi processati prima dell'errore: progresso reale, non 0.
        XCTAssertEqual(at.processed, 2)
        XCTAssertGreaterThan(at.fraction, 0.0)
        XCTAssertFalse(at.isComplete)
    }

    // Insieme vuoto: completed immediato, frazione piena, nessun crash.
    func testEmptyInputCompletesImmediately() {
        let token = CancellationToken()
        let analysis = counter()
        let outcome = analysis.run(over: [], cancellation: token) { progress in
            XCTAssertEqual(progress.fraction, 1.0)
        }
        XCTAssertEqual(outcome, .completed([]))
    }

    // chunkSize < 1 viene alzato a 1 (nessun blocco infinito o divisione per zero).
    func testChunkSizeIsClampedToAtLeastOne() {
        let analysis = ChunkedAnalysis<Int, Int>(chunkSize: 0, initial: 0) { $0 + $1 }
        XCTAssertEqual(analysis.chunkSize, 1)
    }
}
