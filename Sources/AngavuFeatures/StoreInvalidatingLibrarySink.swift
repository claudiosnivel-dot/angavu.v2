import AngavuData
import AngavuDomain

// D-1 (guscio UI) — Sink dei cambi libreria che invalida la cache dei risultati.
//
// Quando PhotoKit segnala un cambio libreria (foto aggiunte/rimosse/modificate),
// i numeri cachati in `AnalysisResultsStore` non sono più freschi: si invalida
// TUTTO, così nessun numero stantìo resta a schermo spacciato per fresco
// (manifesto: numeri veri). Traduce l'`IndexDelta` di dominio prodotto da
// `PhotoLibraryChangeObserver` (T-013) in un'invalidazione della cache.
//
// Il core — `didObserve` ⇒ `invalidateAll` — è l'ORACOLO testabile (un delta
// finto azzera la cache). La REGISTRAZIONE reale dell'osservatore PhotoKit
// (`PhotoLibraryChangeObserver.register()`, che richiede un `PHFetchResult` vivo)
// è integrazione device-only: compilata, runtime dichiarato NON coperto
// (L-COL-006), da cablare quando la UI mantiene un fetch osservabile.
//
// FSE-E3 — lo stesso sink invalida ANCHE la cache dei derivati (feature print/hash/
// nitidezza/residenza), ma PER-ASSET: solo gli id cambiati/rimossi dal delta, così i
// derivati intatti sopravvivono e non si ricalcola l'intera libreria a ogni ritocco.
// Mai un vettore stantìo di un contenuto cambiato (AC-FSE-E3-2).
public final class StoreInvalidatingLibrarySink: LibraryChangeSink {
    private let store: AnalysisResultsStore
    /// Cache dei derivati da invalidare per-asset. `nil` finché il grafo reale non la
    /// cabla (FSE-F): senza store persistito dei derivati non c'è nulla da invalidare.
    private let derivedCache: DerivedResultCache?

    public init(store: AnalysisResultsStore, derivedCache: DerivedResultCache? = nil) {
        self.store = store
        self.derivedCache = derivedCache
    }

    public func didObserve(_ delta: IndexDelta) {
        // Qualunque cambio non vuoto rende stantìi i NUMERI aggregati (conteggi/spazio
        // di più categorie): la cache dei risultati si invalida in blocco, si ricalcola
        // al prossimo ingresso (mai un residuo fresco-per-sbaglio).
        store.invalidateAll()

        // I DERIVATI per-asset, invece, si invalidano solo dove il contenuto è cambiato
        // (changed) o sparito (removed): gli `added` non hanno ancora un derivato.
        guard let derivedCache else { return }
        let ids = delta.changed.map(\.id) + delta.removed
        guard !ids.isEmpty else { return }
        do {
            try derivedCache.invalidate(ids: ids)
        } catch {
            // Se l'invalidazione mirata fallisce, invalida TUTTO piuttosto che rischiare
            // un derivato stantìo: meglio ricalcolare in più che servire un vettore di un
            // contenuto cambiato (onestà, 00-INDEX §6).
            try? derivedCache.invalidateAll()
        }
    }
}
