import AngavuDomain
import Foundation
import Observation

// P0-1 — Store dei risultati d'analisi a livello app (fondazione cache).
//
// Vive SOPRA le view (posseduto da `App/`, iniettato via environment), non nello
// `@State` di una schermata: così i risultati calcolati (numeri dashboard, report,
// review per categoria) sopravvivono alla navigazione avanti-indietro e al ciclo
// background→foreground, invece di essere ricalcolati a ogni comparsa (secondo
// difetto del device-test: rientrando in una categoria si rianalizzava da capo).
//
// FSE-K1 — le entry `.category(...)` sono ora anche PERSISTITE (write-through sul
// port `CategoryResultStoring`, solo id) e lo store è IDRATABILE dalla persistenza
// (`hydrate(assetsById:)`): la cache in memoria diventa una cache leggera sopra un
// record durevole, così i risultati sopravvivono al cold relaunch (bug ricorrente
// «le categorie pesanti riscansionano all'ingresso»: FSE-I1 ripristina senza
// scansionare → lo store era vuoto → rilevatore al tap). Gli aggregati
// (`.dashboard`/`.honestReport`) restano solo in memoria: si ricalcolano dall'indice
// persistito, in fretta. La persistenza NON è best-effort silenziosa: un errore è
// riportato in `lastPersistenceError` (osservabile), mai inghiottito.
//
// La logica pura (set/get/invalidate/prune/hydrate) è l'ORACOLO testabile; la
// sopravvivenza al background è comportamento SwiftUI (View-level, dichiarato non
// coperto, L-COL-006).
//
// Invalidazione (onestà: mai un numero stantìo spacciato per fresco): il chiamante
// invalida dopo un'eliminazione eseguita o quando la libreria cambia
// (`LibraryChangeObserver`, T-013). La persistenza SEGUE la memoria: ciò che è
// invalidato in memoria è rimosso anche dal record, così un'idratazione futura non
// resuscita mai un risultato dichiarato stantìo.
//
// FSE-K2 — ogni review di categoria porta con sé il CHANGE TOKEN di libreria con cui è
// stata calcolata (opaco, persistito nel record); `assessPersistedValidity(using:)`
// chiede al tracker il delta da quel token e applica la `ResultValidityPolicy` pura:
// per ogni categoria `.serve` / `.recompose(touchedIds)` / `.fullRescan`. È il seam che
// K3 consuma al lancio. Un `set` senza token AZZERA il token della chiave (il valore
// non sa a quale stato di libreria corrisponde → al prossimo lancio `.fullRescan`),
// mai un token vecchio ereditato da un valore nuovo.
//
// FSE-K3 — ogni categoria porta anche uno STATO DI FRESCHEZZA presentabile
// (`CategoryFreshness`): `.fresh` (calcolata o verificata contro la libreria corrente),
// `.updating` (servita dalla persistenza mentre il delta del change token è in
// applicazione: un risultato idratato nasce `.updating` finché il ripristino non lo
// verifica) o `.needsFullRescan` (token scaduto/assente: verificabile solo con una
// scansione completa, dichiarata — mai automatica). La View mostra il badge, mai uno
// spinner vuoto né un risultato stantìo spacciato per definitivo.

/// FSE-K3 — Stato di freschezza presentabile di una categoria servita dallo store.
public enum CategoryFreshness: Equatable, Sendable {
    /// Calcolata ora, o verificata valida contro lo stato corrente della libreria.
    case fresh
    /// Servita dalla persistenza, ma il delta di libreria è ancora in applicazione
    /// (ricomposizione in corso): mostrata col badge «in aggiornamento».
    case updating
    /// Non verificabile (token scaduto/assente): serve una scansione completa,
    /// dichiarata all'utente, mai avviata in silenzio.
    case needsFullRescan
}

/// FSE-J2 — Un valore cachato che sa produrre una copia senza certi id (potatura
/// chirurgica dopo un'eliminazione reale). Le review di categoria vi conformano, così
/// lo store può togliere gli id eliminati SENZA rieseguire il rilevatore. No-op
/// (ritorna sé stesso) su insieme vuoto.
public protocol IdentifierPrunable {
    func removing(ids: Set<String>) -> Self
}

/// Chiave di un risultato cachato. Tipizza cosa è memorizzato, così get/set non si
/// confondono tra schermate.
public enum AnalysisResultKey: Hashable, Sendable {
    /// Numeri veri della dashboard (`DashboardScreen`).
    case dashboard
    /// Report onesto (`HonestReportScreen`).
    case honestReport
    /// Review di una categoria, per identificatore di categoria.
    case category(String)
}

/// FSE-K1 — Errore di persistenza RIPORTATO (mai inghiottito): quale operazione è
/// fallita, su quale categoria, e perché. Osservabile dallo store.
public struct AnalysisPersistenceFailure: Error, Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case upsert, remove, removeAll
    }

    public let operation: Operation
    /// Kind della categoria coinvolta; `nil` per `removeAll`.
    public let kind: String?
    public let message: String

    public init(operation: Operation, kind: String?, message: String) {
        self.operation = operation
        self.kind = kind
        self.message = message
    }
}

/// Cache osservabile dei risultati d'analisi, chiave→valore. Il valore è opaco
/// (`Any`): ogni schermata sa quale tipo si aspetta per la propria chiave.
@Observable
public final class AnalysisResultsStore {
    private var storage: [AnalysisResultKey: Any] = [:]
    /// D-1 — Istante in cui ogni valore è stato calcolato, per il badge "aggiornato
    /// X fa". Popolato solo quando il chiamante lo fornisce (`set(_:for:at:)`);
    /// invariato dai `set` senza timestamp (dashboard/report, che non mostrano il
    /// badge). L'età si formatta con `RelativeFreshness` (dominio puro).
    private var timestamps: [AnalysisResultKey: Date] = [:]
    /// FSE-K2 — Change token di libreria (opaco) con cui ogni valore è stato calcolato.
    /// Persistito nel record della categoria; ripristinato dall'idratazione.
    private var libraryTokens: [AnalysisResultKey: Data] = [:]
    /// FSE-K3 — Stato di freschezza per chiave (solo categorie). Assente = non tracciato.
    private var freshness: [AnalysisResultKey: CategoryFreshness] = [:]
    /// FSE-K1 — Persistenza dei risultati per categoria (write-through). Default
    /// null-object: nulla sopravvive al relaunch finché il grafo reale non inietta lo
    /// store SwiftData (`AppEnvironment.categoryResultStore`).
    private let persistence: any CategoryResultStoring
    /// FSE-K1 — Ultimo errore di persistenza, riportato (osservabile), mai inghiottito.
    /// `nil` finché ogni scrittura è riuscita. La memoria resta comunque aggiornata:
    /// un errore di persistenza degrada a «solo in memoria», dichiarato qui.
    public private(set) var lastPersistenceError: AnalysisPersistenceFailure?

    public init(persistence: any CategoryResultStoring = NoCategoryResultStore()) {
        self.persistence = persistence
    }

    /// Valore cachato per la chiave, se presente e del tipo atteso; altrimenti `nil`.
    public func value<Value>(for key: AnalysisResultKey) -> Value? {
        storage[key] as? Value
    }

    /// Memorizza (o rimpiazza) il valore per la chiave. Se `timestamp` è fornito, lo
    /// registra per il badge di freschezza; se `nil`, un eventuale timestamp
    /// precedente resta invariato (il valore è stato ricalcolato ma il chiamante non
    /// traccia la freschezza per questa chiave). FSE-K1: una review di categoria è
    /// anche persistita (write-through). FSE-K2: `libraryToken` è il change token con
    /// cui il valore è stato calcolato; `nil` azzera il token della chiave (mai un token
    /// vecchio spacciato per quello del valore nuovo).
    public func set<Value>(
        _ value: Value,
        for key: AnalysisResultKey,
        at timestamp: Date? = nil,
        libraryToken: Data? = nil
    ) {
        storage[key] = value
        if let timestamp { timestamps[key] = timestamp }
        if let libraryToken {
            libraryTokens[key] = libraryToken
        } else {
            libraryTokens.removeValue(forKey: key)
        }
        // FSE-K3: un valore appena calcolato è fresco per costruzione.
        freshness[key] = .fresh
        persistCategory(key)
    }

    // MARK: - FSE-K3 Freschezza presentabile + validazione del token

    /// FSE-K3 — Stato di freschezza della chiave, se tracciato (`nil` = non tracciato,
    /// p.es. aggregati o chiave assente).
    public func freshness(for key: AnalysisResultKey) -> CategoryFreshness? {
        freshness[key]
    }

    /// FSE-K3 — Imposta lo stato di freschezza di una chiave PRESENTE (no-op su chiave
    /// assente: uno stato senza valore non ha senso). Non tocca la persistenza: la
    /// freschezza è presentazione, il record resta quello del valore.
    public func markFreshness(_ value: CategoryFreshness, for key: AnalysisResultKey) {
        guard storage[key] != nil else { return }
        freshness[key] = value
    }

    /// FSE-K3 — Dichiara il valore della chiave VALIDO rispetto al token dato (esito
    /// `.serve` della policy con delta disgiunto): aggiorna il token in memoria e nel
    /// record persistito, così il prossimo lancio confronta col token più recente
    /// invece di chiedere un delta sempre più lungo (che prima o poi scadrebbe →
    /// `.fullRescan` evitabile). No-op su chiave assente o token già uguale.
    public func markValid(at token: Data, for key: AnalysisResultKey) {
        guard storage[key] != nil, libraryTokens[key] != token else { return }
        libraryTokens[key] = token
        persistCategory(key)
    }

    /// FSE-K2 — Change token con cui il valore per la chiave è stato calcolato, se noto.
    public func libraryToken(for key: AnalysisResultKey) -> Data? {
        libraryTokens[key]
    }

    /// Istante in cui il valore per la chiave è stato calcolato, se tracciato.
    public func timestamp(for key: AnalysisResultKey) -> Date? {
        timestamps[key]
    }

    /// Invalida una singola chiave (valore e timestamp): la prossima lettura ricalcolerà.
    /// FSE-K1: una categoria invalidata è rimossa anche dalla persistenza.
    public func invalidate(_ key: AnalysisResultKey) {
        storage.removeValue(forKey: key)
        timestamps.removeValue(forKey: key)
        libraryTokens.removeValue(forKey: key)
        freshness.removeValue(forKey: key)
        if case .category(let kind) = key {
            report(.remove, kind: kind) { try persistence.remove(kind: kind) }
        }
    }

    /// Invalida tutto: usato dopo un'eliminazione o un cambio di libreria, così
    /// nessun numero stantìo resta a schermo (manifesto: numeri veri). FSE-K1: svuota
    /// anche la persistenza (la persistenza segue la memoria).
    public func invalidateAll() {
        storage.removeAll()
        timestamps.removeAll()
        libraryTokens.removeAll()
        freshness.removeAll()
        report(.removeAll, kind: nil) { try persistence.removeAll() }
    }

    /// FSE-J2 — Potatura CHIRURGICA dopo un'eliminazione reale (censimento B1/C4).
    /// Toglie gli id eliminati da OGNI entry `.category(...)` prunabile — le categorie
    /// non toccate restano in cache così com'erano (nessun ricalcolo del rilevatore, il
    /// nuke di `invalidateAll` le faceva ripartire tutte) — e invalida gli aggregati
    /// (`.dashboard`/`.honestReport`), i cui numeri dipendono dall'intera libreria e
    /// vanno ricalcolati onestamente. No-op su insieme vuoto: nulla cambia, nulla si
    /// invalida. FSE-K1: ogni categoria potata è ripersistita (write-through).
    public func pruneDeleted(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for (key, value) in storage {
            guard case .category = key, let prunable = value as? any IdentifierPrunable else { continue }
            storage[key] = prunable.removing(ids: ids)
            persistCategory(key)
        }
        invalidate(.dashboard)
        invalidate(.honestReport)
    }

    /// Vero quando non c'è nulla in cache (utile ai test e come guardia).
    public var isEmpty: Bool { storage.isEmpty }

    // MARK: - FSE-K1 Persistenza (write-through) e idratazione

    /// Idrata le entry `.category(...)` dai record persistiti, ricostruendo la
    /// `CategoryReviewData` (review + metadati per-id) con gli asset dell'indice.
    /// Regole: (1) la memoria VINCE — una categoria già in cache non è sovrascritta
    /// (è lei che ha scritto la persistenza); (2) un id senza metadati nell'indice
    /// (asset sparito fra i lanci) è escluso dalla review idratata — mai una riga
    /// fantasma; la validità fine col change token è `assessPersistedValidity` (FSE-K2);
    /// (3) il timestamp di freschezza è ripristinato da `computedAt` e il change token
    /// dal record; (4) FSE-K3: ogni categoria idratata nasce `.updating` — servita
    /// subito, ma dichiarata «in verifica» finché il ripristino non applica il delta del
    /// change token (`RestoreHydrationCoordinator`) e la marca `.fresh`. Lancia se la
    /// lettura fallisce.
    ///
    /// - Returns: i kind idratati (per diagnostica/test), in ordine stabile.
    @discardableResult
    public func hydrate(assetsById: [String: LibraryAsset]) throws -> [String] {
        var hydrated: [String] = []
        for record in try persistence.loadAll() {
            let key = AnalysisResultKey.category(record.kind)
            guard storage[key] == nil else { continue }
            let review = CategoryReview(
                keepIds: record.keepIds.filter { assetsById[$0] != nil },
                removableIds: record.removableIds.filter { assetsById[$0] != nil }
            )
            let pairs: [(String, LibraryAsset)] = (review.keepIds + review.removableIds)
                .compactMap { id in assetsById[id].map { (id, $0) } }
            let assets = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            storage[key] = CategoryReviewData(review: review, assets: assets)
            timestamps[key] = record.computedAt
            if let token = record.libraryToken { libraryTokens[key] = token }
            freshness[key] = .updating
            hydrated.append(record.kind)
        }
        return hydrated
    }

    // MARK: - FSE-K2 Validità dei risultati persistiti (change token + delta)

    /// Valuta la validità di OGNI risultato persistito rispetto allo stato corrente
    /// della libreria: legge i record (id + token), chiede al tracker il token corrente
    /// e — SOLO per i token salvati diversi dal corrente — il delta da quel token (una
    /// richiesta per token distinto, mai una per categoria), poi applica la
    /// `ResultValidityPolicy` pura. A token uguale non si interroga nulla: `.serve`.
    /// Lancia se la lettura della persistenza fallisce. È il seam che K3 consuma al
    /// lancio per decidere cosa servire, cosa ricomporre e cosa dichiarare da riscansionare.
    ///
    /// - Returns: decisione per kind (solo i kind persistiti).
    public func assessPersistedValidity(
        using tracker: any LibraryChangeTracking
    ) throws -> [String: ResultValidityDecision] {
        let records = try persistence.loadAll()
        let current = tracker.currentToken()
        var outcomesByToken: [Data: LibraryChangeOutcome] = [:]
        var decisions: [String: ResultValidityDecision] = [:]
        for record in records {
            let saved = SavedCategoryResult(
                kind: record.kind,
                ids: Set(record.keepIds).union(record.removableIds),
                token: record.libraryToken
            )
            var outcome: LibraryChangeOutcome = .unavailable
            if let token = record.libraryToken, let current, token != current {
                if let known = outcomesByToken[token] {
                    outcome = known
                } else {
                    outcome = tracker.changes(since: token)
                    outcomesByToken[token] = outcome
                }
            }
            decisions[record.kind] = ResultValidityPolicy.decide(saved, current: current, outcome: outcome)
        }
        return decisions
    }

    /// Write-through: se la chiave è una categoria e il valore è una review di
    /// categoria, la persiste (solo id + change token). Altri valori sotto `.category`
    /// (usati dai test) e gli aggregati restano solo in memoria. Senza timestamp
    /// tracciato, `computedAt` è l'istante della scrittura (il momento reale in cui il
    /// valore è entrato in cache, mai una data inventata).
    private func persistCategory(_ key: AnalysisResultKey) {
        guard case .category(let kind) = key, let data = storage[key] as? CategoryReviewData else { return }
        let record = CategoryResultRecordValue(
            kind: kind,
            keepIds: data.review.keepIds,
            removableIds: data.review.removableIds,
            libraryToken: libraryTokens[key],
            computedAt: timestamps[key] ?? Date()
        )
        report(.upsert, kind: kind) { try persistence.upsert(record) }
    }

    /// Esegue una scrittura di persistenza e RIPORTA l'eventuale errore (osservabile),
    /// invece di inghiottirlo: la memoria è già aggiornata, la persistenza è
    /// dichiarata mancata.
    private func report(
        _ operation: AnalysisPersistenceFailure.Operation,
        kind: String?,
        _ write: () throws -> Void
    ) {
        do {
            try write()
        } catch {
            lastPersistenceError = AnalysisPersistenceFailure(
                operation: operation, kind: kind, message: String(describing: error)
            )
        }
    }
}
