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
    @State private var didFinishOnboarding = false

    var body: some View {
        NavigationStack {
            if didFinishOnboarding {
                HomeView(environment: .live(context: modelContext))
            } else {
                OnboardingManifestoView(
                    onContinue: { didFinishOnboarding = true },
                    onShowNonGoals: { didFinishOnboarding = true }
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AssetRecord.self, inMemory: true)
}
