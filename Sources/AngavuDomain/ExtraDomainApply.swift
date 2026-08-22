import Foundation

// T-092 — Applicazione confermata di merge contatti e rimozione calendari.
//
// Le azioni extra-foto sono distruttive (fondere contatti, rimuovere una
// sottoscrizione): come tutte le distruttive di Angavu sono HUMAN-GATED
// (L-COL-005). Nessuna parte in autonomia — serve una conferma esplicita — e ogni
// azione riporta un esito onesto: applicata | annullata | fallita. Il gate e la
// mappatura dell'esito sono Domain puro; l'effetto reale (Contacts/EventKit) vive
// dietro i port sotto, implementati nel Data layer e sostituiti da fake nei test.

/// Esito di un'azione extra-foto. `annullata` copre sia l'annullamento esplicito
/// sia il caso di azione non confermata: in entrambi non è stato fatto nulla.
public enum ExtraActionOutcome: Equatable, Sendable {
    /// L'azione è stata eseguita con successo (applicata).
    case applied
    /// L'azione non è stata eseguita: manca la conferma o è stata annullata.
    case cancelled
    /// L'adapter ha riportato un errore (fallita).
    case failed(reason: String)
}

/// Gate di conferma esplicita per un'azione extra-foto. Value type: parte da
/// `proposed` e passa a `confirmed` solo su `confirm()`. Finché non è confermata,
/// l'applicatore rifiuta di agire (AC-092-1).
public struct ExtraActionConfirmation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case proposed
        case confirmed
    }

    public private(set) var state: State

    public init() {
        self.state = .proposed
    }

    /// L'utente conferma esplicitamente l'azione. Idempotente una volta confermata.
    @discardableResult
    public mutating func confirm() -> Bool {
        guard case .proposed = state else { return false }
        state = .confirmed
        return true
    }

    public var isConfirmed: Bool { state == .confirmed }
}

/// Port: esegue il merge effettivo di un cluster di contatti (Data → Contacts).
/// Riporta l'esito reale dell'operazione. I test lo sostituiscono con un fake.
public protocol ContactMerging {
    func merge(_ proposal: ContactMergeProposal) async -> ExtraActionOutcome
}

/// Port: rimuove la sottoscrizione di un calendario (Data → EventKit). Riporta
/// l'esito reale. I test lo sostituiscono con un fake.
public protocol CalendarSubscriptionRemoving {
    func removeSubscription(_ calendar: CalendarEntry) async -> ExtraActionOutcome
}

/// Applicatore puro: fa da gate della conferma davanti ai port dei side-effect.
/// Senza conferma non chiama nemmeno l'adapter (nessun effetto), restituendo
/// `.cancelled`; con conferma delega e propaga l'esito reale.
public enum ExtraActionApplicator {
    /// Applica un merge di contatti solo se confermato (AC-092-1). Con conferma,
    /// l'esito è quello riportato dall'adapter (AC-092-2, lato contatti).
    public static func applyContactMerge(
        _ proposal: ContactMergeProposal,
        confirmation: ExtraActionConfirmation,
        via merger: ContactMerging
    ) async -> ExtraActionOutcome {
        guard confirmation.isConfirmed else { return .cancelled }
        return await merger.merge(proposal)
    }

    /// Applica la rimozione di una sottoscrizione calendario solo se confermata.
    /// Con conferma e adapter `success` l'esito è `.applied` (AC-092-2).
    public static func applyCalendarRemoval(
        _ calendar: CalendarEntry,
        confirmation: ExtraActionConfirmation,
        via remover: CalendarSubscriptionRemoving
    ) async -> ExtraActionOutcome {
        guard confirmation.isConfirmed else { return .cancelled }
        return await remover.removeSubscription(calendar)
    }
}
