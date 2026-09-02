// Guscio dell'app (guscio UI): onboarding-manifesto → Home reale. La Home presenta
// il flusso di scansione cablato coi dati veri (`ScanViewModel` dietro i port
// dell'`AppEnvironment`), con la schermata "cosa NON facciamo" e la selezione del
// tema raggiungibili da lì. FSE-K4: il grafo di sessione (`AppRuntime`: environment
// `.live`, cache dei risultati, observer dei cambi libreria) è posseduto da
// `AngavuApp` e arriva qui via `.environment` — questa view non possiede più stato
// di sessione che un ramo `if` potrebbe azzerare.
import AngavuData
import AngavuDomain
import AngavuFeatures
import SwiftData
import SwiftUI

struct ContentView: View {
    // FSE-K4: grafo di sessione posseduto dall'App (identità stabile per l'intera vita
    // del processo), condiviso da Home, dashboard, categorie e observer.
    @Environment(AppRuntime.self) private var runtime
    // R-00: persistito con `@AppStorage` (prima era `@State`, azzerato a ogni
    // cold-launch → l'onboarding ricompariva a ogni avvio). La chiave è quella
    // dichiarata da `OnboardingGate`, unica fonte del nome. Compare una sola
    // volta per installazione.
    @AppStorage(OnboardingGate.didFinishStorageKey) private var didFinishOnboarding = false
    // R-06: la transizione di fase è animata ma SEMPRE gated su Reduce Motion, con
    // equivalente statico (parità informativa: cambia solo la dissolvenza).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            HomeView(environment: runtime.environment, store: runtime.store)
                .transition(.opacity)
                // FSE-J5/K4: l'osservazione reale dei cambi libreria parte quando la Home
                // appare (dopo l'onboarding, mai prima del permesso foto). Idempotente:
                // una ricomparsa della Home non registra un secondo observer.
                .task { runtime.startObservingLibrary() }
        }
    }

    private func finishOnboarding() {
        withAnimation(reduceMotion ? nil : .easeInOut) {
            didFinishOnboarding = true
        }
    }
}

#Preview {
    ContentPreviewRoot()
}

/// Anteprima con un grafo reale su contenitore in-memory (nessun file, nessun device).
private struct ContentPreviewRoot: View {
    @State private var runtime: AppRuntime? = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(
            for: AssetRecord.self, DerivedRecord.self, CategoryResultRecord.self,
            configurations: configuration
        ) else { return nil }
        return AppRuntime(environment: .live(container: container))
    }()

    var body: some View {
        if let runtime {
            ContentView().environment(runtime)
        } else {
            Text("Anteprima non disponibile: contenitore SwiftData non creato.")
        }
    }
}
