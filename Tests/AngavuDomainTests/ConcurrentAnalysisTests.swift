import Foundation
import XCTest
@testable import AngavuDomain

/// Oracolo logico di FSE-D1 (AC-FSE-D1-1/2/3/4). Domain puro: gira senza device.
/// La velocità reale è un goal validato on-device (§7), mai un AC.
final class ConcurrentAnalysisTests: XCTestCase {

    /// Contatore thread-safe per contare gli step realmente eseguiti.
    private final class AtomicInt {
        private let lock = NSLock()
        private var storage = 0
        func increment() { lock.lock(); storage += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    }

    /// Registratore thread-safe dei progressi osservati, in ordine di pubblicazione.
    private final class ProgressLog {
        private let lock = NSLock()
        private var storage: [Int] = []
        func append(_ value: Int) { lock.lock(); storage.append(value); lock.unlock() }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    // MARK: - AC-FSE-D1-1 — output deterministico nell'ordine d'input

    // N elementi mappati all'indice: l'output è [0..N-1] nell'ordine d'input,
    // qualunque sia l'ordine di completamento. Ripetuto per esercitare il pool.
    func testOutputInInputOrderRegardlessOfCompletion() {
        let count = 400
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 8) { $0 }

        for _ in 0..<10 {
            let token = CancellationToken()
            let outcome = engine.run(over: Array(0..<count), cancellation: token) { _ in }
            XCTAssertEqual(outcome, .completed(Array(0..<count)))
        }
    }

    // Prova esplicita del determinismo: gli indici BASSI finiscono per ULTIMI
    // (sleep inverso), eppure l'output resta ordinato per indice d'input.
    func testDeterministicWhenLowerIndicesFinishLast() {
        let count = 24
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: count) { index in
            Thread.sleep(forTimeInterval: Double(count - index) * 0.001)
            return index * 10
        }

        let token = CancellationToken()
        let outcome = engine.run(over: Array(0..<count), cancellation: token) { _ in }

        XCTAssertEqual(outcome, .completed((0..<count).map { $0 * 10 }))
    }

    // MARK: - AC-FSE-D1-2 — cancellazione: residui non processati

    func testCancellationStopsBeforeRemainingElements() {
        let steps = AtomicInt()
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 2) { index in
            steps.increment()
            return index
        }

        let token = CancellationToken()
        let outcome = engine.run(over: Array(0..<200), cancellation: token) { progress in
            // Appena il progresso raggiunge il primo confine, chiedi la cancellazione.
            if progress.processed >= 2 { token.cancel() }
        }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
        XCTAssertLessThan(at.processed, 200)
        XCTAssertFalse(at.isComplete)
        // Gli elementi residui NON sono stati processati.
        XCTAssertLessThan(steps.value, 200)
    }

    // Cancellato prima di iniziare: nessuno step, esito cancelled a 0.
    func testCancelBeforeStartProcessesNothing() {
        let steps = AtomicInt()
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 4) { index in
            steps.increment()
            return index
        }

        let token = CancellationToken()
        token.cancel()
        let outcome = engine.run(over: Array(0..<50), cancellation: token) { _ in }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
        XCTAssertEqual(at.processed, 0)
        XCTAssertFalse(at.isComplete)
        XCTAssertEqual(steps.value, 0)
    }

    // MARK: - AC-FSE-D1-3 — fallimento esplicito col progresso raggiunto

    func testFailingStepYieldsExplicitFailureWithProgress() {
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 4) { index in
            if index == 0 { throw AnalysisFailure("boom su \(index)") }
            return index
        }

        let token = CancellationToken()
        let outcome = engine.run(over: [0], cancellation: token) { _ in }

        guard case .failed(let reason, let at) = outcome else {
            return XCTFail("atteso .failed, ottenuto \(outcome)")
        }
        XCTAssertEqual(reason, AnalysisFailure("boom su 0"))
        XCTAssertEqual(at.processed, 0)
        XCTAssertFalse(at.isComplete)
    }

    // Con più elementi che lanciano, il motivo riportato è quello dell'indice
    // PIÙ BASSO: deterministico rispetto all'input, non all'ordine di corsa.
    func testFailureReportsLowestIndexDeterministically() {
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 8) { index in
            if index.isMultiple(of: 2) { throw AnalysisFailure("fail \(index)") }
            return index
        }

        for _ in 0..<10 {
            let token = CancellationToken()
            let outcome = engine.run(over: Array(0..<8), cancellation: token) { _ in }
            guard case .failed(let reason, _) = outcome else {
                return XCTFail("atteso .failed, ottenuto \(outcome)")
            }
            XCTAssertEqual(reason, AnalysisFailure("fail 0"))
        }
    }

    // MARK: - AC-FSE-D1-4 — progresso monotòno non decrescente

    func testProgressIsMonotonicNonDecreasing() {
        let count = 300
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 8) { $0 }
        let log = ProgressLog()

        let token = CancellationToken()
        let outcome = engine.run(over: Array(0..<count), cancellation: token) { progress in
            log.append(progress.processed)
        }

        XCTAssertEqual(outcome, .completed(Array(0..<count)))
        let seen = log.values
        XCTAssertFalse(seen.isEmpty)
        for (previous, next) in zip(seen, seen.dropFirst()) {
            XCTAssertLessThanOrEqual(previous, next)
        }
        XCTAssertEqual(seen.last, count)
    }

    // MARK: - DoD — concorrenza = min(configurato, core attivi)

    func testConcurrencyIsClampedToActiveCores() {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)

        // Richiesta enorme → limitata ai core attivi.
        let huge = ConcurrentAnalysis<Int, Int>(concurrency: 10_000) { $0 }
        XCTAssertEqual(huge.maxConcurrency, cores)

        // Richiesta 1 → resta 1 (mai sotto).
        let single = ConcurrentAnalysis<Int, Int>(concurrency: 1) { $0 }
        XCTAssertEqual(single.maxConcurrency, 1)
        XCTAssertEqual(single.concurrency, 1)

        // Valori < 1 alzati a 1 (nessuna divisione per zero, nessun blocco).
        let clamped = ConcurrentAnalysis<Int, Int>(concurrency: 0) { $0 }
        XCTAssertEqual(clamped.concurrency, 1)
    }

    // Insieme vuoto: completed immediato, nessun crash.
    func testEmptyInputCompletesImmediately() {
        let engine = ConcurrentAnalysis<Int, Int>(concurrency: 4) { $0 }
        let token = CancellationToken()
        let outcome = engine.run(over: [], cancellation: token) { progress in
            XCTAssertEqual(progress.fraction, 1.0)
        }
        XCTAssertEqual(outcome, .completed([]))
    }
}
