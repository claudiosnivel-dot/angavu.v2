import AngavuData
import AngavuDomain

// D-1 (guscio UI) — Sink dei cambi libreria che invalida la cache dei risultati.
//
// Quando PhotoKit segnala un cambio libreria (foto aggiunte/rimosse/modificate),
// i numeri cachati in `AnalysisResultsStore` non sono più freschi. Traduce
// l'`IndexDelta` di dominio prodotto da `PhotoLibraryChangeObserver` (T-013) in
// un'invalidazione della cache (manifesto: numeri veri, mai stantìi).
//
// FSE-J5 (censimento C4/B1) — invalidazione CHIRURGICA, non più il nuke. Riusa la
// potatura di FSE-J2 (`AnalysisResultsStore.pruneDeleted`): gli id cambiati/rimossi
// spariscono dalle categorie in cache (le altre categorie restano istantanee, niente
// ricalcolo del rilevatore) e gli aggregati dashboard/report — i cui numeri dipendono
// dall'intera libreria — si invalidano. Su un delta di sole aggiunte gli aggregati si
// invalidano comunque (i conteggi di libreria cambiano) mentre le categorie in cache
// restano intatte. È la stessa onestà del delete reale, applicata ai cambi esterni.
//
// Il core — `didObserve` ⇒ potatura chirurgica — è l'ORACOLO testabile (un delta finto
// pota gli id giusti e invalida gli aggregati, senza nuke: AC-FSE-J5-1). La
// REGISTRAZIONE reale dell'osservatore PhotoKit (`PhotoLibraryChangeObserver.register()`,
// che richiede un `PHFetchResult` vivo) resta device-only, cablata da
// `LibraryObservationCoordinator` e dichiarata NON coperta in CI (L-COL-006, AC-FSE-J5-2).
//
// FSE-E3 — lo stesso sink invalida ANCHE la cache dei derivati (feature print/hash/
// nitidezza/residenza), ma PER-ASSET: solo gli id cambiati/rimossi dal delta, così i
// derivati intatti sopravvivono e non si ricalcola l'intera libreria a ogni ritocco.
// Mai un vettore stantìo di un contenuto cambiato (AC-FSE-E3-2).
public final class StoreInvalidatingLibrarySink: LibraryChangeSink {
    private let store: AnalysisResultsStore
    /// Cache dei derivati da invalidare per-asset. `nil` finché il grafo reale non la
    /// cabla (FSE-J6): senza store persistito dei derivati non c'è nulla da invalidare.
    private let derivedCache: DerivedResultCache?

    public init(store: AnalysisResultsStore, derivedCache: DerivedResultCache? = nil) {
        self.store = store
        self.derivedCache = derivedCache
    }

    public func didObserve(_ delta: IndexDelta) {
        // Gli id realmente toccati (contenuto cambiato o sparito) si potano dalle
        // categorie in cache; `pruneDeleted` invalida anche gli aggregati quando l'insieme
        // non è vuoto. Le categorie non toccate restano in cache (nessun nuke, cache hit
        // al tap successivo) — l'esatto rimedio a «le categorie grosse ripartono» (B1).
        let touchedIds = Set(delta.changed.map(\.id) + delta.removed)
        store.pruneDeleted(ids: touchedIds)

        // Delta di SOLE aggiunte (nessun id da potare → `pruneDeleted` è no-op): i
        // conteggi di libreria sono comunque cambiati, quindi gli aggregati vanno
        // ricalcolati. Le categorie in cache restano intatte: un asset nuovo non modifica
        // una proposta già composta, si riflette al prossimo ricalcolo della categoria.
        if touchedIds.isEmpty, !delta.added.isEmpty {
            store.invalidate(.dashboard)
            store.invalidate(.honestReport)
        }

        // I DERIVATI per-asset si invalidano solo dove il contenuto è cambiato (changed)
        // o sparito (removed): gli `added` non hanno ancora un derivato.
        guard let derivedCache, !touchedIds.isEmpty else { return }
        do {
            try derivedCache.invalidate(ids: Array(touchedIds))
        } catch {
            // Se l'invalidazione mirata fallisce, invalida TUTTO piuttosto che rischiare
            // un derivato stantìo: meglio ricalcolare in più che servire un vettore di un
            // contenuto cambiato (onestà, 00-INDEX §6).
            try? derivedCache.invalidateAll()
        }
    }
}
