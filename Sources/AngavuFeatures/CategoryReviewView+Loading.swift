// CategoryReviewView+Loading — caricamento, cache e indicatore d'avanzamento.
//
// Estratto da `CategoryReviewView.swift` (guscio UI) per tenere il file principale
// sotto il limite di leggibilità (file_length) senza cambiare comportamento —
// stesso idioma di `CategoryReviewView+Rows` / `DashboardView+Sections`. Solo
// SwiftUI, guardato `#if canImport(SwiftUI)`; le decisioni pure vivono in
// `AnalysisProgressPresentation` / `RelativeFreshness` (testate). Strato
// compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

extension CategoryReviewView {

    // MARK: Indicatore d'avanzamento (D-2)
    //
    // La decisione determinato-vs-indeterminato vive nel layer PURO
    // (`AnalysisProgressPresentation`, testato): barra con frazione reale + "X di N"
    // quando il calcolo riporta l'avanzamento, altrimenti spinner etichettato. Mai
    // una frazione fabbricata: la categoria Screenshot legge l'indice in blocco e
    // non espone X/N → resta onestamente indeterminata (la barra reale si accende
    // con i detector a blocchi, C-1). Qui c'è solo la resa SwiftUI.
    @ViewBuilder
    func loadingIndicator(_ progress: AnalysisProgress?) -> some View {
        let pres = AnalysisProgressPresentation(
            progress: progress,
            indeterminateLabel: "Analisi della categoria…"
        )
        if pres.isDeterminate, let fraction = pres.fraction {
            ProgressView(value: fraction) { Text(pres.label) }
        } else {
            ProgressView(pres.label).progressViewStyle(.circular)
        }
    }

    // MARK: Caricamento della sorgente reale (D-1 cache)

    // La composizione della categoria è la parte pesante (fetch dell'indice + per i
    // duplicati/simili hashing SHA-256 / feature print Vision per asset): DEVE girare
    // fuori dal main thread, altrimenti la schermata si blocca come faceva lo scan.
    // `loadIfNeeded` è @MainActor (metodo di View), quindi delega il calcolo a
    // `composeReviewData` (nonisolata → gira sul generic executor) e torna sul main
    // solo per aggiornare `vm`/`loadPhase`. D-1: la cache (`AnalysisResultsStore`)
    // sopra la view rende istantaneo il rientro; `force` (pull-to-refresh) ricalcola.
    @MainActor
    func loadIfNeeded(force: Bool = false) async {
        if !force, loadPhase == .loaded { return }
        // D-1 «Ri-analizza»: un refresh esplicito invalida la cache prima di ricalcolare.
        if force { store.invalidate(cacheKey) }
        // D-1 cache hit: rientro istantaneo, nessun ricalcolo (niente rianalisi da capo).
        // FSE-K1: la decisione hit/miss è la stessa di `CategoryReviewSource.cached`
        // (oracolata: uno store idratato dalla persistenza serve senza rilevatori).
        if !force, let cached = CategoryReviewSource.cached(for: category, in: store) {
            vm = CategoryReviewViewModel(
                review: cached.review,
                assets: cached.assets,
                deleter: environment.assetDeleter
            )
            loadPhase = .loaded
            return
        }
        loadPhase = .loading(nil)
        do {
            // FSE-K2: token catturato PRIMA della composizione (stato che il risultato riflette).
            let libraryToken = environment.changeTracker.currentToken()
            let data = try await CategoryReviewView.composeReviewData(for: category, from: environment)
            // Memorizza col timestamp per il badge di freschezza (D-1) e il change token (K2).
            store.set(data, for: cacheKey, at: Date(), libraryToken: libraryToken)
            vm = CategoryReviewViewModel(
                review: data.review,
                assets: data.assets,
                deleter: environment.assetDeleter
            )
            loadPhase = .loaded
        } catch {
            loadPhase = .failed(String(describing: error))
        }
    }

    /// D-1 — Etichetta di freschezza per il badge, dal timestamp cachato. `Date()` a
    /// tempo di render è View-level (non coperto); la formattazione è pura
    /// (`RelativeFreshness`, oracolo). `nil` quando non c'è un timestamp tracciato.
    var freshnessLabel: String? {
        guard let stamped = store.timestamp(for: cacheKey) else { return nil }
        return RelativeFreshness.label(ageSeconds: Date().timeIntervalSince(stamped))
    }

    /// Calcolo pesante della categoria, ESPLICITAMENTE non isolato al main: awaitandola
    /// da `.task` (main) il corpo gira sul generic executor, così PhotoKit/Vision non
    /// bloccano la UI. Restituisce review + metadati degli asset (A-3).
    nonisolated static func composeReviewData(
        for category: CleanupCategory,
        from environment: AppEnvironment
    ) async throws -> CategoryReviewData {
        try CategoryReviewSource.reviewData(for: category, from: environment)
    }
}
#endif
