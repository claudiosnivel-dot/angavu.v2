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
// È un cache in memoria, non persistenza tra riavvii (fuori scope, §5 del piano).
// La logica pura (set/get/invalidate) è l'ORACOLO testabile; la sopravvivenza al
// background è comportamento SwiftUI (View-level, dichiarato non coperto, L-COL-006).
//
// Invalidazione (onestà: mai un numero stantìo spacciato per fresco): il chiamante
// invalida dopo un'eliminazione eseguita o quando la libreria cambia
// (`LibraryChangeObserver`, T-013). Senza invalidazione il valore resta valido.

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

    public init() {}

    /// Valore cachato per la chiave, se presente e del tipo atteso; altrimenti `nil`.
    public func value<Value>(for key: AnalysisResultKey) -> Value? {
        storage[key] as? Value
    }

    /// Memorizza (o rimpiazza) il valore per la chiave. Se `timestamp` è fornito, lo
    /// registra per il badge di freschezza; se `nil`, un eventuale timestamp
    /// precedente resta invariato (il valore è stato ricalcolato ma il chiamante non
    /// traccia la freschezza per questa chiave).
    public func set<Value>(_ value: Value, for key: AnalysisResultKey, at timestamp: Date? = nil) {
        storage[key] = value
        if let timestamp { timestamps[key] = timestamp }
    }

    /// Istante in cui il valore per la chiave è stato calcolato, se tracciato.
    public func timestamp(for key: AnalysisResultKey) -> Date? {
        timestamps[key]
    }

    /// Invalida una singola chiave (valore e timestamp): la prossima lettura ricalcolerà.
    public func invalidate(_ key: AnalysisResultKey) {
        storage.removeValue(forKey: key)
        timestamps.removeValue(forKey: key)
    }

    /// Invalida tutto: usato dopo un'eliminazione o un cambio di libreria, così
    /// nessun numero stantìo resta a schermo (manifesto: numeri veri).
    public func invalidateAll() {
        storage.removeAll()
        timestamps.removeAll()
    }

    /// FSE-J2 — Potatura CHIRURGICA dopo un'eliminazione reale (censimento B1/C4).
    /// Toglie gli id eliminati da OGNI entry `.category(...)` prunabile — le categorie
    /// non toccate restano in cache così com'erano (nessun ricalcolo del rilevatore, il
    /// nuke di `invalidateAll` le faceva ripartire tutte) — e invalida gli aggregati
    /// (`.dashboard`/`.honestReport`), i cui numeri dipendono dall'intera libreria e
    /// vanno ricalcolati onestamente. No-op su insieme vuoto: nulla cambia, nulla si
    /// invalida.
    public func pruneDeleted(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for (key, value) in storage {
            guard case .category = key, let prunable = value as? any IdentifierPrunable else { continue }
            storage[key] = prunable.removing(ids: ids)
        }
        invalidate(.dashboard)
        invalidate(.honestReport)
    }

    /// Vero quando non c'è nulla in cache (utile ai test e come guardia).
    public var isEmpty: Bool { storage.isEmpty }
}
