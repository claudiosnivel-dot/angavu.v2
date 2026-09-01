import AngavuDomain
import Foundation

// FSE-K3 — Coordinatore del RIPRISTINO dei risultati al lancio (il fix del ripristino).
//
// Origine (diagnosi 2026-09-01, bug RICORRENTE «le categorie pesanti riscansionano
// all'ingresso»): il ripristino FSE-I1 salta la scansione di proposito, quindi lo store
// in memoria restava VUOTO dopo ogni cold relaunch e ogni categoria rigirava il suo
// rilevatore al tap. K1 ha reso i risultati persistenti, K2 ha dato il change token e
// la policy di validità; K3 li CONSUMA al lancio, in tre passi:
//
//   1. `hydrate` — PRIMA di navigare in dashboard: le categorie persistite tornano in
//      memoria (istantanee, stato `.updating`: servite ma dichiarate in verifica).
//   2. `plan` + `apply` — in background: il tracker dice COSA è cambiato dal token
//      salvato (`assessPersistedValidity`, policy K2) → per categoria `.serve` (→ `.fresh`,
//      token allineato), `.recompose` (→ resta `.updating`), `.fullRescan` (→
//      `.needsFullRescan`: stato onesto che invita alla scansione, MAI automatica).
//   3. `recompose` — rigira il SOLO rilevatore delle categorie `.recompose`, una
//      invocazione ciascuna, riusando i derivati persistiti (J6); ripersiste col token
//      corrente (write-through) e marca `.fresh`. Un rilevatore fallito invalida la sua
//      sola categoria (si ricompone al tap, come prima di K3): mai un `.updating` eterno.
//
// Seam TESTABILE (`RestoreHydrationTests`, Livello A: persistenza-spia + tracker-spia +
// rilevatore-spia): i passi sincroni sono l'oracolo; le varianti `async` sono le stesse
// operazioni con i tratti pesanti (lettura indice, delta, composizione) fuori dal main,
// usate dalla `HomeView`. Il cold relaunch REALE è Livello B (`RelaunchCategoryCacheUITests`).
//
// Fuori scope dichiarato: la ricomposizione incrementale dei CLUSTER dei simili — in K3
// la categoria toccata si ricompone INTERA (corretto, non ancora ottimo).

/// Piano di ripristino: le decisioni della policy K2 per ogni categoria persistita e il
/// token corrente con cui ripersistere ciò che viene verificato/ricomposto.
public struct RestorePlan: Equatable, Sendable {
    public let decisions: [String: ResultValidityDecision]
    public let currentToken: Data?

    public init(decisions: [String: ResultValidityDecision], currentToken: Data?) {
        self.decisions = decisions
        self.currentToken = currentToken
    }

    /// Kind da ricomporre, in ordine stabile.
    public var kindsToRecompose: [String] {
        decisions.compactMap { (kind, decision) -> String? in
            if case .recompose = decision { return kind }
            return nil
        }
        .sorted()
    }

    /// Vero se almeno una categoria non è verificabile senza scansione completa.
    public var needsFullRescan: Bool {
        decisions.values.contains(.fullRescan)
    }
}

/// Coordinatore del ripristino: possiede i riferimenti allo store e al grafo, mai un
/// singleton nascosto. Value type: nessuno stato proprio, tutto vive nello store.
public struct RestoreHydrationCoordinator {
    /// Compositore di una categoria (il rilevatore). Iniettabile per l'oracolo
    /// (spia che conta le invocazioni); default = `CategoryReviewSource.reviewData`.
    typealias Composer = (CleanupCategory) throws -> CategoryReviewData

    private let store: AnalysisResultsStore
    private let environment: AppEnvironment

    public init(store: AnalysisResultsStore, environment: AppEnvironment) {
        self.store = store
        self.environment = environment
    }

    // MARK: - Passo 1: idratazione (prima di navigare)

    /// Legge l'INTERO indice persistito (metadati per-id, mai immagini) per
    /// ricostruire le review idratate. Sincrona (oracolo).
    public static func readAssetsById(from environment: AppEnvironment) throws -> [String: LibraryAsset] {
        let assets = try environment.indexReader.assets(matching: .all)
        return Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Variante per la View: funzione `async` NON isolata a un actor — awaitata dal main
    /// gira sul generic executor (stesso idioma di `composeReviewData`), così la lettura
    /// di ~25k record non blocca il primo frame.
    public static func readAssetsByIdOffMain(
        from environment: AppEnvironment
    ) async throws -> [String: LibraryAsset] {
        try readAssetsById(from: environment)
    }

    /// Idrata lo store dai record persistiti usando gli asset dati (già letti, p.es.
    /// off-main). Ogni categoria idratata nasce `.updating`. Lancia se la persistenza
    /// non si legge: in quel caso nulla è idratato e la categoria si ricompone al tap
    /// (comportamento pre-K3, mai un risultato inventato).
    @discardableResult
    public func hydrate(assetsById: [String: LibraryAsset]) throws -> [String] {
        try store.hydrate(assetsById: assetsById)
    }

    /// Comodità sincrona (oracolo): lettura dell'indice + idratazione.
    @discardableResult
    public func hydrate() throws -> [String] {
        try hydrate(assetsById: Self.readAssetsById(from: environment))
    }

    // MARK: - Passo 2: piano di validità (delta del change token)

    /// Chiede allo store la validità di ogni risultato persistito rispetto alla libreria
    /// corrente (K2: una richiesta di delta per token distinto). Sola lettura: non tocca
    /// la memoria dello store, quindi può girare fuori dal main (`plan(store:environment:)`).
    public func plan() throws -> RestorePlan {
        try Self.plan(store: store, environment: environment)
    }

    /// Piano dal solo stato persistito + tracker (sola lettura dello store).
    public static func plan(store: AnalysisResultsStore, environment: AppEnvironment) throws -> RestorePlan {
        let decisions = try store.assessPersistedValidity(using: environment.changeTracker)
        return RestorePlan(decisions: decisions, currentToken: environment.changeTracker.currentToken())
    }

    /// Variante per la View: lettura di persistenza + delta PhotoKit fuori dal main
    /// (funzione `async` non isolata → generic executor).
    public static func planOffMain(
        store: AnalysisResultsStore,
        environment: AppEnvironment
    ) async throws -> RestorePlan {
        try plan(store: store, environment: environment)
    }

    /// Applica il piano allo stato di freschezza: `.serve` → `.fresh` (e token allineato
    /// al corrente, così il prossimo lancio confronta col token più recente);
    /// `.recompose` → `.updating` (resta servita, in attesa del rilevatore);
    /// `.fullRescan` → `.needsFullRescan` (dichiarato, mai una scansione silenziosa).
    public func apply(_ plan: RestorePlan) {
        for (kind, decision) in plan.decisions {
            let key = AnalysisResultKey.category(kind)
            switch decision {
            case .serve:
                if let token = plan.currentToken { store.markValid(at: token, for: key) }
                store.markFreshness(.fresh, for: key)
            case .recompose:
                store.markFreshness(.updating, for: key)
            case .fullRescan:
                store.markFreshness(.needsFullRescan, for: key)
            }
        }
    }

    // MARK: - Passo 3: ricomposizione delle sole categorie toccate

    /// Ricompone le categorie `.recompose` del piano, UNA invocazione del rilevatore
    /// ciascuna, e ripersiste col token corrente. Sincrona (oracolo). Restituisce i kind
    /// ricomposti con successo.
    @discardableResult
    func recompose(_ plan: RestorePlan, compose: Composer) -> [String] {
        var recomposed: [String] = []
        for kind in plan.kindsToRecompose {
            guard let category = CleanupCategory(rawValue: kind) else { continue }
            let composed = try? compose(category)
            if commit(composed, kind: kind, token: plan.currentToken) { recomposed.append(kind) }
        }
        return recomposed
    }

    /// Variante per la View: ogni composizione gira fuori dal main
    /// (`composeOffMain`), il commit torna sul contesto chiamante. Si ferma
    /// cooperativamente se il task è cancellato (p.es. l'utente avvia una nuova
    /// scansione): le categorie non raggiunte restano `.updating` finché la scansione
    /// non le rimpiazza.
    @discardableResult
    public func recompose(_ plan: RestorePlan) async -> [String] {
        var recomposed: [String] = []
        for kind in plan.kindsToRecompose {
            guard !Task.isCancelled, let category = CleanupCategory(rawValue: kind) else { continue }
            let composed = try? await Self.composeOffMain(category, from: environment)
            if commit(composed, kind: kind, token: plan.currentToken) { recomposed.append(kind) }
        }
        return recomposed
    }

    /// Composizione pesante in una funzione `async` non isolata (PhotoKit/Vision non
    /// bloccano la UI): awaitata dal main gira sul generic executor.
    static func composeOffMain(
        _ category: CleanupCategory,
        from environment: AppEnvironment
    ) async throws -> CategoryReviewData {
        try CategoryReviewSource.reviewData(for: category, from: environment)
    }

    /// Commit di una ricomposizione: successo → `set` (write-through col token corrente,
    /// timbro di freschezza, stato `.fresh`); fallimento → la SOLA categoria è invalidata
    /// (si ricompone al tap), mai un `.updating` eterno né un vecchio valore spacciato
    /// per ricomposto.
    private func commit(_ composed: CategoryReviewData?, kind: String, token: Data?) -> Bool {
        let key = AnalysisResultKey.category(kind)
        guard let composed else {
            store.invalidate(key)
            return false
        }
        store.set(composed, for: key, at: Date(), libraryToken: token)
        return true
    }
}

// MARK: - FSE-K3 Presentazione pura dello stato di freschezza

/// Copy del badge di freschezza per categoria (puro, testato): `nil` per `.fresh`
/// (nessun badge oltre a «aggiornato X fa»), un testo onesto per gli altri stati.
public enum CategoryFreshnessPresentation {
    public static func label(for state: CategoryFreshness?) -> String? {
        switch state {
        case .none, .fresh:
            return nil
        case .updating:
            return "In aggiornamento: la libreria è cambiata, ricontrollo questa categoria…"
        case .needsFullRescan:
            return "La libreria è cambiata troppo per verificare questo risultato: rifai l'analisi dalla Home."
        }
    }

    /// Simbolo SF del badge (`nil` quando non c'è badge).
    public static func symbol(for state: CategoryFreshness?) -> String? {
        switch state {
        case .none, .fresh: return nil
        case .updating: return "arrow.triangle.2.circlepath"
        case .needsFullRescan: return "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}
