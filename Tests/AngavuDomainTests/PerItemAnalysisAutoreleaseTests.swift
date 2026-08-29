import XCTest
@testable import AngavuDomain

// FSE-H3 — Oracolo AC-FSE-H3-1: il `serialMap` di `PerItemAnalysis` avvolge ogni
// `transform` in un `autoreleasepool` (dieta memoria del percorso seriale, parità
// col motore concorrente che già lo fa). L'`autoreleasepool` NON deve cambiare
// l'esito osservabile — output in ordine d'input, progresso monotòno, cancellazione
// e fallimento — ma solo il profilo di memoria (device-only, §7, non oracolabile in
// CI). Questi test bloccano una REGRESSIONE di comportamento del serialMap.
//
// Il pool in sé non è osservabile da un test puro; ciò che è osservabile e che qui
// si fissa è l'INVARIANZA del risultato: gli stessi invarianti del motore seriale
// pre-FSE-H3 devono continuare a valere identici.
final class PerItemAnalysisAutoreleaseTests: XCTestCase {
    private let serial = PerItemAnalysis.serial(chunkSize: 8)

    // MARK: AC-FSE-H3-1 — Output in ordine d'input, invariato

    func test_serialMap_producesOutputsInInputOrder() {
        let items = Array(0..<200)
        let outcome = serial.map(items, cancellation: CancellationToken()) { $0 * 2 }

        guard case .completed(let outputs) = outcome else {
            return XCTFail("atteso completed")
        }
        XCTAssertEqual(outputs, items.map { $0 * 2 }, "output = trasformazione in ordine d'input")
    }

    // MARK: AC-FSE-H3-1 — Progresso monotòno non decrescente, arriva a total

    func test_serialMap_progressIsMonotonicAndReachesTotal() {
        let items = Array(0..<200)
        var samples: [AnalysisProgress] = []
        let outcome = serial.map(items, cancellation: CancellationToken(),
                                 progress: { samples.append($0) }) { $0 }

        guard case .completed = outcome else { return XCTFail("atteso completed") }
        XCTAssertFalse(samples.isEmpty, "il progresso deve essere riportato")
        for pair in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.processed, pair.1.processed,
                                     "progresso monotòno non decrescente")
            XCTAssertEqual(pair.0.total, 200, "total costante")
        }
        XCTAssertEqual(samples.last?.processed, 200, "l'ultimo campione raggiunge il total")
    }

    // MARK: AC-FSE-H3-1 — Cancellazione al confine del blocco, parziale onesto

    func test_serialMap_cancellationStopsAtBoundaryWithPartialProgress() {
        let items = Array(0..<50)
        let token = CancellationToken()
        // chunkSize 1 → ogni elemento è un blocco: la cancellazione è rilevata al
        // confine successivo. Cancelliamo dopo aver processato esattamente 10 elementi.
        let oneAtATime = PerItemAnalysis.serial(chunkSize: 1)
        var processed = 0
        let outcome = oneAtATime.map(items, cancellation: token) { value -> Int in
            processed += 1
            if processed == 10 { token.cancel() }
            return value
        }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso cancelled")
        }
        XCTAssertEqual(at.processed, 10, "si ferma al confine dopo i 10 già processati")
        XCTAssertLessThan(at.processed, items.count, "meno di N: nessun parziale spacciato per completo")
    }

    // MARK: AC-FSE-H3-1 — Fallimento esplicito all'indice che lancia

    func test_serialMap_failurePropagatesWithProgress() {
        let items = Array(0..<50)
        let outcome = serial.map(items, cancellation: CancellationToken()) { value -> Int in
            if value == 20 { throw AnalysisFailure("boom a 20") }
            return value
        }

        guard case .failed(let reason, let at) = outcome else {
            return XCTFail("atteso failed")
        }
        XCTAssertEqual(reason, AnalysisFailure("boom a 20"), "motivo esplicito, mai silenzioso")
        XCTAssertEqual(at.processed, 20, "progresso = elementi completati prima del fallimento")
    }

    // MARK: AC-FSE-H3-1 — Parità: identico a una map di riferimento senza pool

    func test_serialMap_matchesReferenceMapping() {
        let items = Array(0..<137)
        let outcome = serial.map(items, cancellation: CancellationToken()) { $0 * $0 }

        let reference: AnalysisOutcome<[Int]> = .completed(items.map { $0 * $0 })
        XCTAssertEqual(outcome, reference,
                       "l'autoreleasepool non cambia il risultato, solo la memoria")
    }

    // MARK: AC-FSE-H3-1 — Input vuoto: completed immediato

    func test_serialMap_emptyInputCompletesImmediately() {
        let outcome = serial.map([Int](), cancellation: CancellationToken()) { $0 }
        XCTAssertEqual(outcome, .completed([]), "input vuoto → completed vuoto")
    }
}
