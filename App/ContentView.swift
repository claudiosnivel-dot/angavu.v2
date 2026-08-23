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

    var body: some View {
        NavigationStack {
            if OnboardingGate.shouldPresentOnboarding(hasFinishedOnboarding: didFinishOnboarding) {
                OnboardingManifestoView(
                    onContinue: { didFinishOnboarding = true }
                )
            } else {
                HomeView(environment: .live(context: modelContext))
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AssetRecord.self, inMemory: true)
}
