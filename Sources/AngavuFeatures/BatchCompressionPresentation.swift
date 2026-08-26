import AngavuDomain

// B-2d — Presentazione PURA del batch di compressione (nessun import SwiftUI).
//
// Le decisioni osservabili della schermata batch che meritano un oracolo: il
// riepilogo della selezione (quanti, totale stimato dei SOLI selezionati, quanti
// non stimabili) e il riepilogo della coda in esecuzione (progresso determinato,
// esiti aggregati, output reale). La resa SwiftUI resta l'unico strato
// «compilato-ma-non-testato» (L-COL-006).
//
// Onestà: il totale del risparmio è la somma dei saving STIMATI dei soli
// selezionati stimabili (sempre stima, mai esatto); i selezionati senza spec sono
// contati a parte e dichiarati, mai sommati come 0.

/// Riepilogo della selezione corrente rispetto alla stima di batch.
public struct BatchCompressionSummary: Equatable, Sendable {
    /// Numero di video selezionati.
    public let selectedCount: Int
    /// L'avvio è consentito (almeno un selezionato). Opt-in: falso di default.
    public let canStart: Bool
    /// Somma dei saving STIMATI dei soli selezionati con spec nota (sempre stima).
    public let selectedEstimatedSavingBytes: Int64
    /// Quanti dei selezionati NON hanno stima (spec assente): dichiarati, mai sommati.
    public let selectedUnestimableCount: Int

    public init(estimate: BatchCompressionEstimate, selection: BatchCompressionSelection) {
        let selectedIds = selection.selected
        var total: Int64 = 0
        for item in estimate.perItem where selectedIds.contains(item.id) {
            total += item.saving.bytes
        }
        self.selectedEstimatedSavingBytes = total
        self.selectedUnestimableCount = estimate.unestimableIds.reduce(0) {
            $0 + (selectedIds.contains($1) ? 1 : 0)
        }
        self.selectedCount = selection.selectedCount
        self.canStart = selection.canStart
    }
}

/// Riepilogo della coda in esecuzione / conclusa. Progresso SEMPRE determinato.
public struct BatchCompressionRunSummary: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Ci sono ancora item da processare.
        case running
        /// Coda conclusa (tutti con esito, o cancellata).
        case done
    }

    public let phase: Phase
    /// Numeratore del progresso determinato (item con esito).
    public let processed: Int
    /// Denominatore del progresso (totale in coda).
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    public let cancelled: Int
    /// Byte reali dell'output riuscito (mai stima: è output vero).
    public let totalOutputBytes: Int64

    public init(run: BatchCompressionRun) {
        self.phase = run.isFinished ? .done : .running
        self.processed = run.progress.processed
        self.total = run.total
        self.succeeded = run.succeededCount
        self.failed = run.failedCount
        self.cancelled = run.cancelledCount
        self.totalOutputBytes = run.totalOutputBytes
    }

    /// Frazione di avanzamento (0…1), determinata. 0 su coda vuota.
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}

/// Testi onesti riusati dalla View del batch (unica fonte, come le altre schermate).
public enum BatchCompressionCopy {
    /// Nota della rete di sicurezza: ogni originale resta recuperabile ~30 gg.
    public static let safetyNet = CompressionPresentation.safetyNetText

    /// Avviso onesto quando la stima copre solo i primi `shown` di `totalCandidates`
    /// video (cap per dimensione, per non ricalcolare su migliaia): dichiarato, mai
    /// silenzioso. `nil` quando la stima copre tutti i candidati.
    public static func estimateCapNotice(shown: Int, totalCandidates: Int) -> String? {
        guard totalCandidates > shown else { return nil }
        return "Stima sui \(shown) video più grandi (di \(totalCandidates)): "
            + "liberano più spazio. Gli altri restano comprimibili singolarmente."
    }
}
