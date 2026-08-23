// Rifinitura HIG R-06 — vocabolario di feedback aptico sui momenti-firma.
//
// I momenti che l'utente "sente" (fine scansione, apertura anteprima distruttiva,
// conferma/completamento, fallimento, avanzamento) meritano un feedback aptico
// coerente e PARSIMONIOSO — un vocabolario per rarità, un solo owner per evento,
// nessun doppio-buzz. Questa è un'utility mono-utente: canale APTICO, non suoni.
//
// Il layer PURO (evento → livello) è l'ORACOLO testabile; la traduzione al tipo
// `SensoryFeedback` di SwiftUI e il modificatore che rispetta il toggle utente
// vivono dietro `#if canImport(SwiftUI)`. Il feedback è sempre subordinato al
// consenso: se l'utente lo disattiva, nessuna vibrazione.

/// Evento-firma dell'app che merita un feedback aptico. Insieme chiuso e piccolo:
/// la parsimonia è parte del design (troppi buzz = rumore, non segnale).
public enum FeedbackEvent: Equatable, Sendable, CaseIterable {
    /// Conferma leggera o avanzamento (es. passo onboarding, consenso dato).
    case actionAdvance
    /// Apertura di un'anteprima DISTRUTTIVA (eliminazione in arrivo): allerta tenue.
    case destructivePreview
    /// Operazione completata con successo (eliminazione, compressione, fusione).
    case success
    /// Operazione fallita: l'errore si sente, non solo si legge.
    case failure
}

/// Livello di feedback, indipendente dalla piattaforma. Mappa 1:1 sugli haptics di
/// sistema; tenerlo separato dall'evento permette di testare la mappa senza SwiftUI.
public enum FeedbackLevel: Hashable, Sendable {
    case impactLight
    case warning
    case success
    case error
}

extension FeedbackEvent {
    /// La mappa evento → livello. Totale e deterministica: un evento, un livello.
    public var level: FeedbackLevel {
        switch self {
        case .actionAdvance: return .impactLight
        case .destructivePreview: return .warning
        case .success: return .success
        case .failure: return .error
        }
    }
}

/// Preferenza utente per il feedback aptico. Gli haptics non hanno un interruttore
/// di sistema globale, quindi lo offriamo noi (default: attivo). Persistita come il
/// tema, con degrado sicuro al default.
public enum HapticsPreference {
    public static let storageKey = "angavu.haptics"
    /// Default esplicito quando la chiave non è mai stata scritta.
    public static let defaultEnabled = true
}

#if canImport(SwiftUI)
import SwiftUI

extension FeedbackLevel {
    /// Traduzione al feedback aptico di sistema. Unico punto di mappatura.
    public var sensoryFeedback: SensoryFeedback {
        switch self {
        case .impactLight: return .impact(weight: .light)
        case .warning: return .warning
        case .success: return .success
        case .error: return .error
        }
    }
}

/// Emette il feedback aptico dell'evento quando `trigger` cambia, SOLO se l'utente
/// non ha disattivato gli haptics. `resolve` sceglie l'evento dal cambio di stato
/// (o `nil` per non emettere nulla): un solo owner per momento, nessun doppio-buzz.
private struct HapticFeedbackModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let resolve: (Trigger, Trigger) -> FeedbackEvent?
    @AppStorage(HapticsPreference.storageKey) private var enabled = HapticsPreference.defaultEnabled

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { old, new in
            guard enabled, let event = resolve(old, new) else { return nil }
            return event.level.sensoryFeedback
        }
    }
}

extension View {
    /// Aggancia il feedback aptico dei momenti-firma a un valore osservabile.
    /// `resolve(old, new)` restituisce l'evento da segnalare, o `nil`.
    public func hapticFeedback<Trigger: Equatable>(
        on trigger: Trigger,
        _ resolve: @escaping (Trigger, Trigger) -> FeedbackEvent?
    ) -> some View {
        modifier(HapticFeedbackModifier(trigger: trigger, resolve: resolve))
    }
}
#endif
