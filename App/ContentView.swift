// Schermata segnaposto di `foundation`. Le schermate reali arrivano con il
// macrotask `ui_shell` (onboarding-manifesto, report onesto).
import SwiftUI
import AngavuFeatures

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Angavu")
                .font(.largeTitle.bold())
            Text("Fondamenta pronte.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
