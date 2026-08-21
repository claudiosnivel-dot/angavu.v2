import Foundation

// Motore d'analisi a blocchi, cancellabile con stop cooperativo (T-004).
//
// Lezioni field-fix Android portate qui come invarianti di tipo:
//  • niente eterno 0%: l'esito è SEMPRE esplicito (completed | cancelled | failed)
//    e porta con sé il progresso raggiunto;
//  • dieta low-RAM: elaborazione a blocchi, un blocco alla volta;
//  • fuori dal main: il motore è sincrono e agnostico; il chiamante lo mette
//    off-main. Nessun import di PhotoKit/Vision/AVFoundation (altitudine).

/// Progresso monotòno di un'analisi. `processed` non supera mai `total`.
public struct AnalysisProgress: Equatable {
    public let processed: Int
    public let total: Int

    public init(processed: Int, total: Int) {
        let safeTotal = max(0, total)
        self.total = safeTotal
        self.processed = min(max(0, processed), safeTotal)
    }

    /// Frazione 0…1. Un totale nullo è considerato completo.
    public var fraction: Double {
        total == 0 ? 1.0 : Double(processed) / Double(total)
    }

    /// Vero solo quando tutti gli elementi sono stati processati.
    public var isComplete: Bool { processed == total }
}

/// Motivo di fallimento, esplicito e ispezionabile (mai un errore silenzioso).
public struct AnalysisFailure: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Esito esplicito di un'analisi. `cancelled` e `failed` riportano il progresso
/// raggiunto: così un blocco a "0% infinito" è impossibile per costruzione.
public enum AnalysisOutcome<Result>: Equatable where Result: Equatable {
    case completed(Result)
    case cancelled(at: AnalysisProgress)
    case failed(reason: AnalysisFailure, at: AnalysisProgress)
}

/// Token di cancellazione cooperativo, sicuro fra thread.
public final class CancellationToken {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    /// Richiede la cancellazione. Idempotente.
    public func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    /// Vero se è stata richiesta la cancellazione.
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// Contratto del motore d'analisi cancellabile che i rilevatori riuseranno.
public protocol CancellableAnalysis {
    associatedtype Element
    associatedtype Result: Equatable

    /// Elabora `items` a blocchi con checkpoint di cancellazione fra un blocco e
    /// l'altro, riportando progresso monotòno, e restituisce un esito esplicito.
    func run(
        over items: [Element],
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) -> AnalysisOutcome<Result>
}

/// Analisi a blocchi generica: piega gli elementi in un accumulatore, un blocco
/// alla volta, controllando la cancellazione al confine di ogni blocco.
public struct ChunkedAnalysis<Element, Result: Equatable>: CancellableAnalysis {
    public let chunkSize: Int
    private let initial: Result
    private let step: (Result, Element) throws -> Result

    /// - Parameters:
    ///   - chunkSize: elementi per blocco (>= 1; valori minori vengono alzati a 1).
    ///   - initial: accumulatore iniziale.
    ///   - step: trasformazione per elemento; se lancia, l'esito è `failed`.
    public init(
        chunkSize: Int = 64,
        initial: Result,
        step: @escaping (Result, Element) throws -> Result
    ) {
        self.chunkSize = max(1, chunkSize)
        self.initial = initial
        self.step = step
    }

    public func run(
        over items: [Element],
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) -> AnalysisOutcome<Result> {
        let total = items.count
        var processed = 0
        var accumulator = initial

        // Progresso di partenza: mai partire senza un segnale (no "0% muto").
        progress(AnalysisProgress(processed: processed, total: total))

        var index = 0
        while index < total {
            // Checkpoint di cancellazione AL CONFINE del blocco: gli elementi
            // restanti non vengono processati.
            if cancellation.isCancelled {
                return .cancelled(at: AnalysisProgress(processed: processed, total: total))
            }

            let end = min(index + chunkSize, total)
            while index < end {
                do {
                    accumulator = try step(accumulator, items[index])
                } catch let failure as AnalysisFailure {
                    return .failed(
                        reason: failure,
                        at: AnalysisProgress(processed: processed, total: total)
                    )
                } catch {
                    return .failed(
                        reason: AnalysisFailure(String(describing: error)),
                        at: AnalysisProgress(processed: processed, total: total)
                    )
                }
                processed += 1
                index += 1
            }

            // Progresso a fine blocco: monotòno non decrescente.
            progress(AnalysisProgress(processed: processed, total: total))
        }

        // Il totale è raggiunto SOLO qui: esito completed.
        return .completed(accumulator)
    }
}
