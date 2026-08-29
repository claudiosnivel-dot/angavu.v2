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
    @State private var resultsStore = AnalysisResultsStore()
    // FSE-J5 (censimento C4): possiede il sink + l'observer PhotoKit dei cambi libreria
    // (l'observer trattiene il sink solo `weak`, quindi il possesso forte vive qui, per
    // l'intera sessione). Costruito e avviato una volta quando la Home appare; la
    // registrazione reale è device-only (AC-FSE-J5-2), la logica d'invalidazione è
    // oracolata in CI (AC-FSE-J5-1).
    @State private var libraryObserver: LibraryObservationCoordinator?

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
            HomeView(environment: .live(container: modelContext.container), store: resultsStore)
                .transition(.opacity)
                .task { startLibraryObservation() }
        }
    }

    /// FSE-J5 — Avvia (una volta) l'osservazione dei cambi libreria: al variare della
    /// libreria il sink pota gli id toccati dalle categorie in cache e invalida gli
    /// aggregati (invalidazione chirurgica, mai il nuke). Idempotente.
    private func startLibraryObservation() {
        guard libraryObserver == nil else { return }
        let coordinator = LibraryObservationCoordinator(store: resultsStore)
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
        .modelContainer(for: AssetRecord.self, inMemory: true)
}
