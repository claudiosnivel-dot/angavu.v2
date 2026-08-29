import AngavuData
import AngavuDomain
#if canImport(Photos)
import Photos
#endif

// FSE-J5 (censimento C4) — Coordinatore della registrazione dell'observer dei cambi
// libreria.
//
// Il sink dell'invalidazione (`StoreInvalidatingLibrarySink`) e l'observer PhotoKit
// (`PhotoLibraryChangeObserver`) devono restare VIVI per l'intera sessione: l'observer
// trattiene il sink solo `weak`, quindi qualcuno deve possederli entrambi con
// riferimento forte, o si deregistrano subito. Questo coordinatore è quel possessore:
// l'app lo tiene in `@State` (ContentView) e lo avvia una volta.
//
// `start()` registra l'observer su un fetch VIVO di tutta la libreria: è integrazione
// device-only (richiede l'accesso reale alla libreria foto), dichiarata NON coperta in
// CI (L-COL-006, AC-FSE-J5-2). La LOGICA d'invalidazione del sink resta invece oracolata
// in CI (AC-FSE-J5-1, `StoreInvalidatingLibrarySinkTests`).
public final class LibraryObservationCoordinator {
    private let sink: StoreInvalidatingLibrarySink
    #if canImport(Photos)
    private var observer: PhotoLibraryChangeObserver?
    #endif

    public init(store: AnalysisResultsStore, derivedCache: DerivedResultCache? = nil) {
        self.sink = StoreInvalidatingLibrarySink(store: store, derivedCache: derivedCache)
    }

    #if canImport(Photos)
    /// Registra l'observer su TUTTI gli asset della libreria (foto e video). Idempotente:
    /// una seconda chiamata non registra un secondo observer. Device-only: senza accesso
    /// reale alla libreria il fetch è vuoto e nessun delta arriva (mai un falso segnale).
    public func start() {
        guard observer == nil else { return }
        let observer = PhotoLibraryChangeObserver(
            initialFetch: PHAsset.fetchAssets(with: nil),
            sink: sink
        )
        observer.register()
        self.observer = observer
    }

    /// Deregistra l'observer (idempotente). Chiamato quando la Home lascia la scena.
    public func stop() {
        observer?.unregister()
        observer = nil
    }

    deinit { stop() }
    #endif
}
