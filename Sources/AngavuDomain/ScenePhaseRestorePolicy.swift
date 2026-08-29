import Foundation

// FSE-J4 — Ciclo di vita: `scenePhase` + restore affidabile (censimento C6). Cuore PURO.
//
// Difetto osservato on-device: l'app non gestiva affatto il ciclo di vita. Al ritorno da
// background riparte dal tasto gigante, e il ripristino di FSE-I1 (un solo `.task` al primo
// appear) è fragile: non copre il resume-da-sospensione e dipende dai tempismi di SwiftUI.
//
// Questa è la POLICY pura che, data una TRANSIZIONE di fase (dallo stato precedente a quello
// corrente) e lo stato dell'indice persistito, decide l'azione:
//   • verso background → PERSIST: iOS può terminare l'app memory-heavy → si persiste un
//     marker (schermata/scansione) PRIMA, così un cold relaunch atterra dove si era;
//   • ritorno reale al foreground (era in background) → RESTORE|FRESH riusando la policy di
//     lancio di FSE-I1 (indice non vuoto → dashboard; vuoto → tasto di scansione), MAI una
//     ri-scansione forzata;
//   • transizioni transitorie (`.inactive`, active→active, ecc.) → NONE: il contesto resta.
//
// Onestà (manifesto: numeri veri). La policy NON produce numeri e NON elimina nulla: decide
// solo il ramo. Il ripristino atterra sui numeri LETTI DALL'INDICE PERSITITO (freschi per
// costruzione), col caveat device finché la residenza non è misurata (FSE-G1); l'invalidazione
// su cambio libreria (FSE-E3) resta attiva → mai una cifra vecchia spacciata per fresca.
//
// Altitudine: solo Foundation. Nessuna dipendenza di piattaforma — la fase SwiftUI
// (`ScenePhase`) è mappata su `AppLifecyclePhase` dalla View (strato compilato-non-testato,
// L-COL-006); qui entrano solo l'enum puro e un `Int` (il conteggio dell'indice).

/// Fase del ciclo di vita dell'app, versione di dominio (indipendente da SwiftUI). La View
/// mappa `@Environment(\.scenePhase)` su questo enum prima di consultare la policy.
public enum AppLifecyclePhase: Equatable, Sendable {
    /// In primo piano e interattiva.
    case active
    /// Transitoria (chiamata in arrivo, Control Center, App Switcher a metà): il contesto
    /// va PRESERVATO, non è né un vero background né un vero ritorno al foreground.
    case inactive
    /// In background: iOS può sospendere o TERMINARE l'app memory-heavy.
    case background
}

/// Azione decisa dalla policy per una transizione di fase.
public enum ScenePhaseAction: Equatable, Sendable {
    /// Nessuna azione: transizione transitoria, il contesto resta com'è.
    case none
    /// Persisti lo stato (marker schermata/scansione) prima che iOS possa terminare l'app.
    case persist
    /// Al foreground: ripristina i risultati (indice non vuoto) — la View decide la schermata
    /// esatta dal marker persistito, senza forzare una nuova scansione.
    case restore
    /// Al foreground: nessun dato indicizzato (primo avvio) → mostra il tasto di scansione.
    case fresh
}

/// Policy PURA del ciclo di vita. L'oracolo di dominio (`ScenePhaseRestorePolicyTests`) prova
/// le direzioni richieste: verso background → `persist`; background→active con indice non
/// vuoto → `restore`, vuoto → `fresh`; transizioni transitorie → `none`.
public enum ScenePhaseRestorePolicy {
    /// Decisione pura dalla transizione di fase e dal conteggio dell'indice persistito.
    ///
    /// - Parameters:
    ///   - previous: la fase SIGNIFICATIVA precedente (la View collassa gli `.inactive`
    ///     transitori, così una transizione reale background→active arriva qui diretta).
    ///   - current: la fase corrente.
    ///   - indexedCount: conteggio dell'indice persistito (una lettura fallita → 0 dal
    ///     chiamante), usato SOLO al ritorno al foreground per scegliere restore vs fresh.
    public static func action(
        from previous: AppLifecyclePhase,
        to current: AppLifecyclePhase,
        indexedCount: Int
    ) -> ScenePhaseAction {
        switch (previous, current) {
        case (_, .background):
            // Sta andando in background: persisti PRIMA che iOS possa terminare l'app.
            return .persist
        case (.background, .active):
            // Ritorno reale dal background: riusa la policy di lancio di FSE-I1 (unica fonte
            // della regola restore/fresh — indice non vuoto → dashboard, vuoto → scan).
            switch LaunchRestorePolicy.decide(indexedCount: indexedCount) {
            case .restore: return .restore
            case .fresh: return .fresh
            }
        default:
            // `.inactive` transitorio, active→active, background→inactive, ecc.: il contesto
            // resta, nessuna azione (mai un ripristino su una transizione che non è un vero
            // ritorno dal background).
            return .none
        }
    }
}

/// FSE-J4 — Chiave di persistenza (UserDefaults via `@AppStorage`) del marker «l'utente
/// stava guardando i risultati». Scritto dalla View sull'azione `.persist` (verso background),
/// riletto sull'azione `.restore` per atterrare sulla schermata ESATTA in cui si era, mai su
/// un tasto di scansione fantasma. Solo una `String` (nessuna dipendenza SwiftUI qui).
public enum LifecycleMarker {
    public static let wasViewingResultsKey = "angavu.lifecycle.wasViewingResults"
}
