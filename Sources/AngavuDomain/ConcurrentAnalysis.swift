import Foundation

// Motore d'analisi CONCORRENTE, cancellabile (FSE-D1).
//
// Affianca `ChunkedAnalysis` (T-004) — non lo sostituisce: dove il seriale è già
// adeguato (screenshot, grandi/vecchi) resta ChunkedAnalysis. Qui gli elementi
// CPU/decodifica-bound (feature print Vision, nitidezza, hashing) girano in
// PARALLELO, con gli stessi invarianti di onestà del motore seriale:
//
//  • esito SEMPRE esplicito (`completed | cancelled | failed`) col progresso
//    raggiunto — un blocco a "0% infinito" è impossibile per costruzione;
//  • output nell'ordine d'INPUT (per-indice), INDIPENDENTE dall'ordine di
//    completamento → gli oracoli restano stabili nonostante il parallelismo;
//  • progresso monotòno non decrescente, serializzato da un lock (nessun
//    arretramento anche con più worker che pubblicano insieme);
//  • dieta low-RAM: al più `maxConcurrency` elementi in volo, `autoreleasepool`
//    per worker (i pixel decodificati non si accumulano fino al jetsam).
//
// Altitudine: Domain puro — solo Foundation/Dispatch. Nessun import PhotoKit/
// Vision/AVFoundation. I rilevatori reali lo adotteranno in FSE-D2, dietro i
// port sincroni già esistenti.

/// Stato condiviso di una passata concorrente, protetto da un unico lock.
///
/// Isola OGNI accesso mutabile: i worker chiamano solo `recordSuccess`/
/// `recordFailure`, così la correttezza sotto concorrenza vive in un solo posto.
private final class ConcurrentAnalysisState<Output> {
    private let lock = NSLock()
    private let total: Int
    private var results: [Int: Output] = [:]
    private var processedCount = 0
    private var firstFailure: (index: Int, failure: AnalysisFailure)?

    init(total: Int) { self.total = total }

    /// Registra il risultato all'indice d'input e pubblica il progresso.
    /// La chiamata a `progress` è sotto lock → serializzata e monotòna.
    func recordSuccess(
        index: Int,
        output: Output,
        progress: (AnalysisProgress) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        results[index] = output
        processedCount += 1
        progress(AnalysisProgress(processed: processedCount, total: total))
    }

    /// Registra un fallimento tenendo quello dell'indice PIÙ BASSO: il motivo
    /// riportato è deterministico rispetto all'input, non all'ordine di corsa.
    func recordFailure(index: Int, _ failure: AnalysisFailure) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = firstFailure, existing.index <= index { return }
        firstFailure = (index, failure)
    }

    var processed: Int {
        lock.lock()
        defer { lock.unlock() }
        return processedCount
    }

    func failure() -> AnalysisFailure? {
        lock.lock()
        defer { lock.unlock() }
        return firstFailure?.failure
    }

    /// Risultati in ordine d'input, oppure `nil` se manca un indice: un buco non
    /// deve MAI passare per "completo" (onestà: niente lista parziale spacciata).
    func orderedResults() -> [Output]? {
        lock.lock()
        defer { lock.unlock() }
        var ordered: [Output] = []
        ordered.reserveCapacity(total)
        for index in 0..<total {
            guard let value = results[index] else { return nil }
            ordered.append(value)
        }
        return ordered
    }
}

/// Motore concorrente: mappa ogni elemento in parallelo, cancellabile a onde.
public struct ConcurrentAnalysis<Element, Output: Equatable> {
    /// Concorrenza richiesta (>= 1; valori minori vengono alzati a 1).
    public let concurrency: Int
    private let transform: (Element) throws -> Output

    /// - Parameters:
    ///   - concurrency: worker desiderati; il grado effettivo è comunque limitato
    ///     ai core attivi (vedi `maxConcurrency`).
    ///   - transform: lavoro per elemento; se lancia, l'esito è `failed`.
    public init(
        concurrency: Int,
        transform: @escaping (Element) throws -> Output
    ) {
        self.concurrency = max(1, concurrency)
        self.transform = transform
    }

    /// Parallelismo effettivo: `min(configurato, core attivi)`. Satura la CPU
    /// senza far esplodere la memoria (decodifiche in volo limitate).
    public var maxConcurrency: Int {
        min(concurrency, max(1, ProcessInfo.processInfo.activeProcessorCount))
    }

    /// Elabora `items` in parallelo a onde di `maxConcurrency`, con checkpoint di
    /// cancellazione fra un'onda e l'altra. Restituisce i risultati in ordine
    /// d'input; l'esito porta sempre il progresso raggiunto.
    public func run(
        over items: [Element],
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) -> AnalysisOutcome<[Output]> {
        let total = items.count

        // Progresso di partenza: mai un "0% muto".
        progress(AnalysisProgress(processed: 0, total: total))
        if total == 0 { return .completed([]) }

        let state = ConcurrentAnalysisState<Output>(total: total)
        let waveSize = maxConcurrency
        var start = 0

        while start < total {
            // Checkpoint AL CONFINE dell'onda: le onde restanti non partono
            // (elementi residui non processati) su cancellazione o fallimento.
            if cancellation.isCancelled {
                return .cancelled(at: progressPoint(state, total))
            }
            if let failure = state.failure() {
                return .failed(reason: failure, at: progressPoint(state, total))
            }

            let end = min(start + waveSize, total)
            runWave(items: items, start: start, count: end - start,
                    into: state, progress: progress)
            start = end
        }

        return finalize(state, total: total)
    }

    // MARK: - Passi interni

    /// Esegue una singola onda in parallelo; ogni worker tocca un solo indice.
    private func runWave(
        items: [Element],
        start: Int,
        count: Int,
        into state: ConcurrentAnalysisState<Output>,
        progress: (AnalysisProgress) -> Void
    ) {
        DispatchQueue.concurrentPerform(iterations: count) { offset in
            autoreleasepool {
                let index = start + offset
                do {
                    let output = try transform(items[index])
                    state.recordSuccess(index: index, output: output, progress: progress)
                } catch let failure as AnalysisFailure {
                    state.recordFailure(index: index, failure)
                } catch {
                    state.recordFailure(index: index, AnalysisFailure(String(describing: error)))
                }
            }
        }
    }

    /// Esito a onde terminate: un fallimento osservato vince sul completamento;
    /// un buco nei risultati è un fallimento esplicito, mai un "completo" finto.
    private func finalize(
        _ state: ConcurrentAnalysisState<Output>,
        total: Int
    ) -> AnalysisOutcome<[Output]> {
        if let failure = state.failure() {
            return .failed(reason: failure, at: progressPoint(state, total))
        }
        guard let ordered = state.orderedResults() else {
            return .failed(
                reason: AnalysisFailure("risultato mancante nella composizione concorrente"),
                at: progressPoint(state, total)
            )
        }
        return .completed(ordered)
    }

    private func progressPoint(
        _ state: ConcurrentAnalysisState<Output>,
        _ total: Int
    ) -> AnalysisProgress {
        AnalysisProgress(processed: state.processed, total: total)
    }
}
