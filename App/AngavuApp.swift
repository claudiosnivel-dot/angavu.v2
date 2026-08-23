// Angavu iOS — punto d'ingresso dell'app SwiftUI.
//
// L'app è un target Xcode (fuori da `swift build`) che referenzia il package
// SwiftPM locale. Il deployment target iOS 17.0 è dichiarato in
// Config/Shared.xcconfig (fonte canonica) e in App/project.yml (spec XcodeGen).
import SwiftUI
import AngavuDomain
import AngavuFeatures

@main
struct AngavuApp: App {
    /// Preferenza tema persistita; `Sistema` finché l'utente non sceglie.
    @AppStorage(ThemePreference.storageKey) private var theme: ThemeChoice = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                // nil per `.system` → segue iOS; altrimenti forza chiaro/scuro.
                .preferredColorScheme(theme.preferredColorScheme)
        }
    }
}
