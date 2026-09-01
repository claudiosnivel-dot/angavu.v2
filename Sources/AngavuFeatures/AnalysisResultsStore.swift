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
    /// anche persistita (write-through).
    public func set<Value>(_ value: Value, for key: AnalysisResultKey, at timestamp: Date? = nil) {
        storage[key] = value
        if let timestamp { timestamps[key] = timestamp }
        persistCategory(key)
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
    /// fantasma; la validità fine (change token) è FSE-K2; (3) il timestamp di
    /// freschezza è ripristinato da `computedAt`. Lancia se la lettura fallisce.
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
            hydrated.append(record.kind)
        }
        return hydrated
    }

    /// Write-through: se la chiave è una categoria e il valore è una review di
    /// categoria, la persiste (solo id). Altri valori sotto `.category` (usati dai
    /// test) e gli aggregati restano solo in memoria. Senza timestamp tracciato,
    /// `computedAt` è l'istante della scrittura (il momento reale in cui il valore
    /// è entrato in cache, mai una data inventata).
    private func persistCategory(_ key: AnalysisResultKey) {
        guard case .category(let kind) = key, let data = storage[key] as? CategoryReviewData else { return }
        let record = CategoryResultRecordValue(
            kind: kind,
            keepIds: data.review.keepIds,
            removableIds: data.review.removableIds,
            libraryToken: nil,
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
