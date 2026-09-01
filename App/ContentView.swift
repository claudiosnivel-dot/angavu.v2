// Guscio dell'app (guscio UI): onboarding-manifesto → Home reale. La Home presenta
// il flusso di scansione cablato coi dati veri (`ScanViewModel` dietro i port
// dell'`AppEnvironment`), con la schermata "cosa NON facciamo" e la selezione del
// tema raggiungibili da lì. L'`AppEnvironment` di produzione (`.live`) è costruito
// qui dal `ModelContext` SwiftData installato in `AngavuApp`.
import AngavuData
import AngavuDomain
import AngavuFeatures
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    // R-00: persistito con `@AppStorage` (prima era `@State`, azzerato a ogni
    // cold-launch → l'onboarding ricompariva a ogni avvio). La chiave è quella
    // dichiarata da `OnboardingGate`, unica fonte del nome. Compare una sola
    // volta per installazione.
    @AppStorage(OnboardingGate.didFinishStorageKey) private var didFinishOnboarding = false
    // R-06: la transizione di fase è animata ma SEMPRE gated su Reduce Motion, con
    // equivalente statico (parità informativa: cambia solo la dissolvenza).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // P0-1: la cache dei risultati d'analisi vive QUI, sopra le view: sopravvive alla
    // navigazione e al ciclo background→foreground (non è `@State` di una schermata,
    // che verrebbe azzerato a ogni ricomparsa). Iniettata nella Home e a valle.
    // FSE-K1: costruita in `activateHome()` insieme al grafo, perché riceve la
    // persistenza reale dei risultati per categoria (`environment.categoryResultStore`,
    // write-through) — così le review sopravvivono al cold relaunch. L'idratazione al
    // lancio è FSE-K3 (dopo la policy di validità col change token, FSE-K2).
    @State private var resultsStore: AnalysisResultsStore?
    // FSE-J5 (censimento C4): possiede il sink + l'observer PhotoKit dei cambi libreria
    // (l'observer trattiene il sink solo `weak`, quindi il possesso forte vive qui, per
    // l'intera sessione). Costruito e avviato una volta quando la Home appare; la
    // registrazione reale è device-only (AC-FSE-J5-2), la logica d'invalidazione è
    // oracolata in CI (AC-FSE-J5-1).
    @State private var libraryObserver: LibraryObservationCoordinator?
    // FSE-J6 (censimento C3): l'`AppEnvironment.live` di produzione è costruito UNA volta e
    // condiviso dalla Home (scansione) e dall'observer FSE-J5 — così il sink invalida la
    // STESSA cache dei derivati che la scansione consulta (prima era `nil`: l'invalidazione
    // per-asset di J5 era un no-op). Costruito quando la Home appare, per non toccare
    // `modelContext.container` fuori dal ciclo di vista.
    @State private var environment: AppEnvironment?

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if OnboardingGate.shouldPresentOnboarding(hasFinishedOnboarding: didFinishOnboarding) {
            OnboardingManifestoView(onContinue: finishOnboarding)
                .transition(.opacity)
        } else {
            Group {
                if let environment, let resultsStore {
                    HomeView(environment: environment, store: resultsStore)
                } else {
                    // Un solo frame mentre il grafo si costruisce (dentro la dissolvenza
                    // dall'onboarding): `activateHome()` lo popola immediatamente in `.task`.
                    Color.clear
                }
            }
            .transition(.opacity)
            .task { activateHome() }
        }
    }

    /// FSE-J5/J6 — Costruisce (una volta) il grafo di produzione e avvia l'osservazione
    /// dei cambi libreria, condividendo la STESSA `AppEnvironment` (e quindi la stessa
    /// cache dei derivati) fra Home e observer: al variare della libreria il sink pota gli
    /// id toccati dalle categorie in cache, invalida gli aggregati e invalida i derivati
    /// per-asset (invalidazione chirurgica, mai il nuke). Idempotente.
    private func activateHome() {
        let environment = self.environment ?? .live(container: modelContext.container)
        self.environment = environment
        let store = resultsStore ?? AnalysisResultsStore(persistence: environment.categoryResultStore)
        resultsStore = store
        guard libraryObserver == nil else { return }
        let coordinator = LibraryObservationCoordinator(
            store: store,
            derivedCache: environment.derivedCache
        )
        #if canImport(Photos)
        coordinator.start()
        #endif
        libraryObserver = coordinator
    }

    private func finishOnboarding() {
        withAnimation(reduceMotion ? nil : .easeInOut) {
            didFinishOnboarding = true
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [AssetRecord.self, DerivedRecord.self, CategoryResultRecord.self], inMemory: true
        )
}
