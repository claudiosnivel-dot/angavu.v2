import Foundation

// FSE-K2 (Domain) — Policy PURA di validità dei risultati per categoria persistiti.
//
// Un risultato salvato (FSE-K1) è valido SSE il token di libreria con cui fu calcolato
// combacia col token corrente, oppure il delta persistente da quel token NON tocca
// nessuno dei suoi id. Se il delta interseca gli id della categoria, SOLO quella
// categoria va ricomposta (mai una ricomposizione globale). Token scaduto o assente →
// scansione completa DICHIARATA (mai servire in silenzio risultati stantìi).
// Deterministica, zero piattaforma: l'oracolo è `ResultValidityPolicyTests`.

/// Un risultato di categoria come salvato: gli id che lo compongono (keep + removable)
/// e il token di libreria al momento del calcolo (`nil` = ignoto).
public struct SavedCategoryResult: Equatable, Sendable {
    public let kind: String
    public let ids: Set<String>
    public let token: Data?

    public init(kind: String, ids: Set<String>, token: Data?) {
        self.kind = kind
        self.ids = ids
        self.token = token
    }
}

/// Decisione per una categoria salvata.
public enum ResultValidityDecision: Equatable, Sendable {
    /// Servire dalla persistenza così com'è: nessun rilevatore.
    case serve
    /// Ricomporre SOLO questa categoria; `touchedIds` = i suoi id toccati dal delta.
    case recompose(touchedIds: Set<String>)
    /// Il risultato non è verificabile (token scaduto/assente): scansione completa,
    /// dichiarata all'utente — mai automatica silenziosa.
    case fullRescan
}

public enum ResultValidityPolicy {
    /// Decide per ogni categoria salvata. `outcome` è l'esito di `changes(since:)` dal
    /// token salvato; è consultato SOLO quando il token salvato esiste e differisce dal
    /// corrente (a token uguale non c'è nulla da chiedere).
    public static func decide(
        saved: [SavedCategoryResult],
        current: Data?,
        outcome: LibraryChangeOutcome
    ) -> [String: ResultValidityDecision] {
        var decisions: [String: ResultValidityDecision] = [:]
        decisions.reserveCapacity(saved.count)
        for result in saved {
            decisions[result.kind] = decide(result, current: current, outcome: outcome)
        }
        return decisions
    }

    /// Regola per una singola categoria:
    ///   • token salvato assente o token corrente assente → `.fullRescan`;
    ///   • token uguale → `.serve`;
    ///   • token diverso: `.expired`/`.unavailable` → `.fullRescan`; delta vuoto o
    ///     disgiunto dagli id → `.serve`; delta che interseca → `.recompose(touched)`.
    public static func decide(
        _ saved: SavedCategoryResult,
        current: Data?,
        outcome: LibraryChangeOutcome
    ) -> ResultValidityDecision {
        guard let savedToken = saved.token, let current else { return .fullRescan }
        if savedToken == current { return .serve }
        switch outcome {
        case .expired, .unavailable:
            return .fullRescan
        case .delta(let delta):
            if delta.isEmpty { return .serve }
            let touched = delta.touchedIds.intersection(saved.ids)
            return touched.isEmpty ? .serve : .recompose(touchedIds: touched)
        }
    }

    /// Applica il delta a un insieme di id salvati: gli id in `deleted` sono POTATI
    /// anche se ricompaiono in `inserted` (id cambiato → delete+insert: il nuovo id
    /// entra solo dalla ricomposizione del rilevatore, mai per match). `updated` e
    /// `inserted` non aggiungono nulla qui: ricomporre è compito del rilevatore.
    public static func pruned(ids: Set<String>, applying delta: LibraryChangeDelta) -> Set<String> {
        ids.subtracting(delta.deleted)
    }
}
