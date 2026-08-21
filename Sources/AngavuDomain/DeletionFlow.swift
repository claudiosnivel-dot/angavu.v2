import Foundation

// T-050 — Gate di anteprima obbligatoria prima di ogni eliminazione.
//
// Rete di sicurezza intoccabile (feasibility §5): NESSUN percorso raggiunge
// l'eliminazione saltando l'anteprima. Modellato come macchina a stati pura nel
// Domain, testabile senza device: la transizione a `confirmed` è possibile solo
// da un'anteprima esplicitamente mostrata E accettata. L'insieme confermato
// coincide, per costruzione, con quello previewato.

/// Macchina a stati dell'eliminazione. Value type: ogni transizione muta lo stato
/// solo se legale, altrimenti lo lascia invariato e segnala il rifiuto.
public struct DeletionFlow: Equatable, Sendable {

    /// Stato del flusso. Le transizioni legali sono:
    /// `idle → previewing → confirmed → deleting`. L'anteprima porta un flag
    /// `accepted`: solo `previewing(accepted: true)` può passare a `confirmed`.
    public enum State: Equatable, Sendable {
        case idle
        case previewing(assets: [String], accepted: Bool)
        case confirmed(assets: [String])
        case deleting(assets: [String])
    }

    public private(set) var state: State

    public init() {
        self.state = .idle
    }

    /// Mostra l'anteprima per gli asset selezionati. Consentito solo da `idle` e
    /// con una selezione non vuota. Non marca ancora l'anteprima come accettata.
    @discardableResult
    public mutating func presentPreview(for ids: [String]) -> Bool {
        guard case .idle = state, !ids.isEmpty else { return false }
        state = .previewing(assets: ids, accepted: false)
        return true
    }

    /// L'utente accetta l'anteprima mostrata. Consentito solo mentre si è in
    /// `previewing`; mantiene l'insieme previewato invariato.
    @discardableResult
    public mutating func acceptPreview() -> Bool {
        guard case .previewing(let ids, _) = state else { return false }
        state = .previewing(assets: ids, accepted: true)
        return true
    }

    /// Gate: passa a `confirmed` SOLO da un'anteprima accettata. Ogni tentativo da
    /// `idle` o da un'anteprima non accettata è rifiutato (anteprima obbligatoria).
    @discardableResult
    public mutating func confirm() -> Bool {
        guard case .previewing(let ids, let accepted) = state, accepted else { return false }
        state = .confirmed(assets: ids)
        return true
    }

    /// Avvia l'eliminazione effettiva. Consentito solo da `confirmed`.
    @discardableResult
    public mutating func beginDeleting() -> Bool {
        guard case .confirmed(let ids) = state else { return false }
        state = .deleting(assets: ids)
        return true
    }

    /// Insieme di asset attualmente in gioco (previewato / confermato / in
    /// eliminazione). Vuoto quando `idle`.
    public var pendingAssets: [String] {
        switch state {
        case .idle:
            return []
        case .previewing(let ids, _), .confirmed(let ids), .deleting(let ids):
            return ids
        }
    }
}
