// Guscio dell'app (macrotask `ui_shell`): onboarding-manifesto → home, con la
// schermata "cosa NON facciamo" raggiungibile. Il report onesto
// (`HonestReportView`) è pronto in AngavuFeatures e verrà alimentato dai dati
// veri della libreria (dashboard/library_index) nel cablaggio dati.
import AngavuFeatures
import SwiftUI

struct ContentView: View {
    @State private var didFinishOnboarding = false

    var body: some View {
        NavigationStack {
            if didFinishOnboarding {
                HomeView()
            } else {
                OnboardingManifestoView(
                    onContinue: { didFinishOnboarding = true },
                    onShowNonGoals: { didFinishOnboarding = true }
                )
            }
        }
    }
}

/// Home minimale del guscio: dà accesso alla schermata dei non-goals. Le sezioni
/// del cuore-foto si agganciano qui nel cablaggio successivo.
private struct HomeView: View {
    var body: some View {
        List {
            NavigationLink {
                NonGoalsView()
            } label: {
                Label("Cosa NON facciamo", systemImage: "xmark.seal")
            }
        }
        .navigationTitle("Angavu")
    }
}

#Preview {
    ContentView()
}
