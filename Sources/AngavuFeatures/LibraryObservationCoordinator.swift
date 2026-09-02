import AngavuData
import AngavuDomain
import Foundation
#if canImport(Photos)
import Photos
#endif

// FSE-J5 (censimento C4) — Coordinatore della registrazione dell'observer dei cambi
// libreria.
//
// Il sink dell'invalidazione (`StoreInvalidatingLibrarySink`) e l'observer PhotoKit
// (`PhotoLibraryChangeObserver`) devono restare VIVI per l'intera sessione: l'observer
// trattiene il sink solo `weak`, quindi qualcuno deve possederli entrambi con
// riferimento forte, o si deregistrano subito. Questo coordinatore è quel possessore.
// FSE-K4: è posseduto dall'`App` (via `AppRuntime`, `@State` in `AngavuApp`), non più da
// una view intermedia che un ramo `if` può ricreare.
//
// FSE-K4: il coordinatore È il sink registrato su PhotoKit e inoltra ogni delta al
// `CoalescingLibraryChangeSink`, che assorbe le raffiche di notifiche in UN solo delta
// (unione degli id, consegnato sul main actor) verso il sink d'invalidazione chirurgica.
// Un delta vuoto (solo riordino, `hasMoves`) non produce alcuna invalidazione.
//
// `start()` registra l'observer su un fetch VIVO di tutta la libreria: è integrazione
// device-only (richiede l'accesso reale alla libreria foto), dichiarata NON coperta in
// CI (L-COL-006, AC-FSE-J5-2). La LOGICA d'invalidazione e la coalescenza restano
// oracolate in CI (`StoreInvalidatingLibrarySinkTests`, `ObserverCoalescingTests`).
public final class LibraryObservationCoordinator: LibraryChangeSink {
    private let coalescer: CoalescingLibraryChangeSink
    #if canImport(Photos)
    private var observer: PhotoLibraryChangeObserver?
    #endif

    public init(
        store: AnalysisResultsStore,
        derivedCache: DerivedResultCache? = nil,
        debounce: TimeInterval = CoalescingLibraryChangeSink.defaultDebounce,
        scheduler: any FlushScheduling = MainActorFlushScheduler()
    ) {
        let sink = StoreInvalidatingLibrarySink(store: store, derivedCache: derivedCache)
        self.coalescer = CoalescingLibraryChangeSink(downstream: sink, debounce: debounce, scheduler: scheduler)
    }

    /// Ingresso di ogni delta osservato (da PhotoKit o da un test): coalescito, mai
    /// inoltrato uno a uno.
    public func didObserve(_ delta: IndexDelta) {
        coalescer.didObserve(delta)
    }

    #if canImport(Photos)
    /// Registra l'observer su TUTTI gli asset della libreria (foto e video). Idempotente:
    /// una seconda chiamata non registra un secondo observer. Device-only: senza accesso
    /// reale alla libreria il fetch è vuoto e nessun delta arriva (mai un falso segnale).
    public func start() {
        guard observer == nil else { return }
        let observer = PhotoLibraryChangeObserver(
            initialFetch: PHAsset.fetchAssets(with: nil),
            sink: self
        )
        observer.register()
        self.observer = observer
    }

    /// Deregistra l'observer (idempotente).
    public func stop() {
        observer?.unregister()
        observer = nil
    }

    deinit { stop() }
    #endif
}
