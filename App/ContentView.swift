// Guscio dell'app (macrotask `ui_shell`): onboarding-manifesto → home, con la
// schermata "cosa NON facciamo" e la selezione del tema raggiungibili. Il report
// onesto (`HonestReportView`) è pronto in AngavuFeatures e viene alimentato dai
// dati veri della libreria nel cablaggio (`wiring`).
import AngavuDomain
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

/// Home minimale del guscio: dà accesso ai non-goals e al tema. Le sezioni del
/// cuore-foto si agganciano qui nel cablaggio (`wiring`).
private struct HomeView: View {
    @AppStorage(ThemePreference.storageKey) private var theme: ThemeChoice = .system
    @State private var showThemeSettings = false

    var body: some View {
        List {
            NavigationLink {
                NonGoalsView()
            } label: {
                Label("Cosa NON facciamo", systemImage: "xmark.seal")
            }
            Button {
                showThemeSettings = true
            } label: {
                Label("Tema: \(theme.label)", systemImage: theme.symbolName)
            }
        }
        .navigationTitle("Angavu")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showThemeSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Impostazioni tema")
            }
        }
        .sheet(isPresented: $showThemeSettings) {
            NavigationStack {
                ThemeSettingsView(choice: $theme)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fatto") { showThemeSettings = false }
                        }
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
