// Angavu iOS — punto d'ingresso dell'app SwiftUI.
//
// L'app è un target Xcode (fuori da `swift build`) che referenzia il package
// SwiftPM locale. Il deployment target iOS 17.0 è dichiarato in
// Config/Shared.xcconfig (fonte canonica) e in App/project.yml (spec XcodeGen).
import SwiftUI
import SwiftData
import AngavuData
import AngavuDomain
import AngavuFeatures

@main
struct AngavuApp: App {
    /// Preferenza tema persistita; `Sistema` finché l'utente non sceglie.
    @AppStorage(ThemePreference.storageKey) private var theme: ThemeChoice = .system

    /// FSE-A1: telemetria d'app. Costruita all'avvio del processo (l'App `@main` è
    /// istanziata una sola volta): il subscriber MetricKit è registrato qui, mai in
    /// una schermata secondaria. Ritenuto per l'intera vita del processo.
    private let telemetry = AppTelemetry()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // nil per `.system` → segue iOS; altrimenti forza chiaro/scuro.
                .preferredColorScheme(theme.preferredColorScheme)
        }
        // Indice SwiftData on-device (zero backend): il ModelContext creato qui
        // alimenta l'`AppEnvironment.live` costruito in ContentView. FSE-J6: lo schema
        // include anche `DerivedRecord` così i derivati (digest…) persistono fra i lanci.
        .modelContainer(for: [AssetRecord.self, DerivedRecord.self])
    }
}
