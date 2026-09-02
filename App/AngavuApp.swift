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

    /// Indice SwiftData on-device (zero backend). FSE-J6: lo schema include anche
    /// `DerivedRecord` così i derivati (digest…) persistono fra i lanci; FSE-K1:
    /// `CategoryResultRecord` così i RISULTATI per categoria (solo id) sopravvivono al
    /// cold relaunch. Creato qui, una volta, perché alimenta il grafo di sessione.
    private let container: ModelContainer

    /// FSE-K4 — Il grafo di sessione (`AppEnvironment.live` + cache dei risultati +
    /// observer dei cambi libreria) è POSSEDUTO dall'`App` (guida Apple: lo stato di
    /// modello con identità stabile vive in `@State` dell'`App` e viaggia via
    /// `.environment`), non più da una view intermedia che un ramo `if` può ricreare
    /// azzerando cache e observer. Un'unica istanza per l'intera vita del processo.
    @State private var runtime: AppRuntime

    init() {
        let container = AngavuApp.makeContainer()
        self.container = container
        _runtime = State(initialValue: AppRuntime(environment: .live(container: container)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(runtime)
                // nil per `.system` → segue iOS; altrimenti forza chiaro/scuro.
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .modelContainer(container)
    }

    /// Contenitore SwiftData dell'app. Un fallimento qui (schema/negozio corrotto) è
    /// irrecuperabile per costruzione — lo stesso esito del modificatore
    /// `.modelContainer(for:)` usato prima di K4: si preferisce fermarsi a un'app che
    /// finge di funzionare senza persistenza (onestà).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([AssetRecord.self, DerivedRecord.self, CategoryResultRecord.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("Impossibile creare il ModelContainer SwiftData: \(error)")
        }
    }
}
