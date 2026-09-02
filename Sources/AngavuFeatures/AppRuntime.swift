import AngavuDomain
import Foundation
import Observation

// FSE-K4 (hardening, guida Apple «Managing model data in your app») — Il grafo di
// sessione posseduto dall'`App`.
//
// Prima di K4 lo store dei risultati, il grafo `AppEnvironment.live` e il coordinatore
// dell'observer erano `@State` di `ContentView`, costruiti nel `.task` della Home: uno
// stato che vive in una view intermedia ha l'identità di QUELLA view — un ramo `if`
// (onboarding ↔ Home) o una ricomposizione può ricrearla e azzerarlo, e con esso la
// cache e l'observer (un'altra strada per «le categorie pesanti ripartono»). L'oggetto di
// sessione vive quindi nell'`App` (`@State` in `AngavuApp`, istanziata una sola volta per
// processo) ed è iniettato via `.environment` a tutta la gerarchia: identità stabile per
// l'intera vita del processo, un'unica istanza per store/grafo/observer.
//
// `@Observable` solo per viaggiare nell'environment SwiftUI (`.environment(_:)` richiede
// `Observable`): le sue proprietà sono costanti, non c'è stato osservato qui — lo stato
// osservabile è dentro `AnalysisResultsStore`.
@Observable
public final class AppRuntime {
    /// Grafo di produzione (adapter reali dietro i port), costruito una volta.
    public let environment: AppEnvironment
    /// Cache dei risultati d'analisi, con persistenza write-through (FSE-K1).
    public let store: AnalysisResultsStore
    /// Possessore forte di sink + observer PhotoKit dei cambi libreria (FSE-J5/K4).
    public let libraryObserver: LibraryObservationCoordinator

    /// `observerScheduler`: scheduler del flush coalescito (default: main actor, ~0,5 s);
    /// iniettabile nei test di Livello A per far scattare la finestra a mano.
    public init(environment: AppEnvironment, observerScheduler: any FlushScheduling = MainActorFlushScheduler()) {
        self.environment = environment
        let store = AnalysisResultsStore(persistence: environment.categoryResultStore)
        self.store = store
        // La STESSA cache dei derivati che la scansione consulta (FSE-J6): l'invalidazione
        // per-asset dell'observer tocca ciò che la scansione legge.
        self.libraryObserver = LibraryObservationCoordinator(
            store: store,
            derivedCache: environment.derivedCache,
            scheduler: observerScheduler
        )
    }

    /// Avvia l'osservazione reale dei cambi libreria (idempotente; device-only: senza
    /// accesso alla libreria nessun delta arriva). Chiamata quando la Home appare, così
    /// la registrazione non precede il permesso foto.
    public func startObservingLibrary() {
        #if canImport(Photos)
        libraryObserver.start()
        #endif
    }
}
