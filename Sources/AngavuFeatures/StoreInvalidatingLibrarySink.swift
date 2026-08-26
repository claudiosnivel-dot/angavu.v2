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
public final class StoreInvalidatingLibrarySink: LibraryChangeSink {
    private let store: AnalysisResultsStore

    public init(store: AnalysisResultsStore) {
        self.store = store
    }

    public func didObserve(_ delta: IndexDelta) {
        // Qualunque cambio non vuoto rende stantìi i numeri: si ricalcola al
        // prossimo ingresso. Non si tenta un'invalidazione selettiva per-asset:
        // un delta tocca conteggi/spazio di più categorie → invalidare tutto è la
        // scelta onesta e semplice (mai un residuo fresco-per-sbaglio).
        store.invalidateAll()
    }
}
