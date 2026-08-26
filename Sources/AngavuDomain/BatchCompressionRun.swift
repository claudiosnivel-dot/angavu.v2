import Foundation

// B-2c — Orchestrazione della coda di compressione (RIDUTTORE PURO).
//
// È l'oracolo testabile del batch: data una coda ordinata di id e un flusso di
// esiti per-item, traccia il progresso DETERMINATO (X/N), aggrega gli esiti, e
// gestisce la cancellazione. La parte impura (invocare davvero l'exporter
// AVFoundation per item) vive nel driver async in `AngavuFeatures`; qui non si
// importa nulla di piattaforma — il Domain resta puro (altitudine).
//
// Invarianti (manifesto rete di sicurezza + onestà):
//   • un FALLIMENTO per-item NON aborta il batch: si registra e si prosegue;
//   • la CANCELLAZIONE lascia i residui NON processati (dichiarati `.cancelled`),
//     mentre gli esiti già ottenuti restano — nessun sorgente è toccato per essi;
//   • il progresso è sempre determinato (elementi con esito / totale), mai una
//     rotella indeterminata spacciata per avanzamento.

/// Stato della coda di compressione di un batch di video. Puro, deterministico.
public struct BatchCompressionRun: Equatable, Sendable {

    /// Esito di un singolo video nella coda.
    public enum ItemState: Equatable, Sendable {
        /// Non ancora processato.
        case pending
        /// Compresso e sostituito: byte reali dell'output (mai stima).
        case succeeded(outputBytes: Int64)
        /// Fallito: motivo esplicito; il sorgente resta intatto.
        case failed(reason: String)
        /// Non processato per cancellazione: sorgente intatto.
        case cancelled
    }

    /// Coda ordinata degli id da comprimere (l'ordine è quello della selezione).
    public let queue: [String]
    /// Esiti paralleli alla coda (stesso indice). Partono tutti `.pending`.
    public private(set) var states: [ItemState]
    /// Vero dopo una richiesta di cancellazione.
    public private(set) var isCancelled: Bool

    public init(queue: [String]) {
        self.queue = queue
        self.states = Array(repeating: .pending, count: queue.count)
        self.isCancelled = false
    }

    /// Indice del prossimo item da processare (primo `.pending`), o `nil` se la coda
    /// è finita o cancellata. È il cursore che il driver async segue in ordine.
    public var nextPendingIndex: Int? {
        guard !isCancelled else { return nil }
        return states.firstIndex(of: .pending)
    }

    /// Registra l'esito dell'item all'indice dato. Ignora indici fuori range o item
    /// già con esito (idempotenza: un esito non si sovrascrive).
    public mutating func record(_ state: ItemState, at index: Int) {
        guard states.indices.contains(index), states[index] == .pending else { return }
        states[index] = state
    }

    /// Cancella la coda: i `.pending` residui diventano `.cancelled` (dichiarati non
    /// processati); gli esiti già registrati restano invariati.
    public mutating func cancel() {
        isCancelled = true
        for index in states.indices where states[index] == .pending {
            states[index] = .cancelled
        }
    }

    // MARK: - Osservabili (presentazione / oracolo)

    /// Numero totale di video nella coda.
    public var total: Int { queue.count }

    /// Numero di video con un esito (success/failed/cancelled): il numeratore del
    /// progresso determinato.
    public var completedCount: Int {
        states.reduce(0) { $0 + ($1 == .pending ? 0 : 1) }
    }

    /// Vero quando non resta alcun `.pending` da processare (o è cancellata).
    public var isFinished: Bool { nextPendingIndex == nil }

    /// Progresso DETERMINATO (riusa il tipo del motore d'analisi): X/N e frazione.
    public var progress: AnalysisProgress {
        AnalysisProgress(processed: completedCount, total: total)
    }

    /// Numero di compressioni riuscite.
    public var succeededCount: Int {
        states.reduce(0) { acc, state in
            if case .succeeded = state { return acc + 1 }
            return acc
        }
    }

    /// Numero di compressioni fallite (il batch non si è fermato per esse).
    public var failedCount: Int {
        states.reduce(0) { acc, state in
            if case .failed = state { return acc + 1 }
            return acc
        }
    }

    /// Numero di video non processati per cancellazione.
    public var cancelledCount: Int {
        states.reduce(0) { $0 + ($1 == .cancelled ? 1 : 0) }
    }

    /// Byte reali totali degli output riusciti (mai stima: sono output veri).
    public var totalOutputBytes: Int64 {
        states.reduce(0) { acc, state in
            if case .succeeded(let bytes) = state { return acc + bytes }
            return acc
        }
    }
}
