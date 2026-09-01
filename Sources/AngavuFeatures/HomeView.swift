// HomeView — la schermata cardine dopo l'onboarding, riscritta per il flusso
// "Shazam" (Fase E). Apre con UN SOLO tasto gigante centrale che, al tocco, chiede
// il permesso e avvia la scansione con una sola barra d'avanzamento (E-1/E-2); a
// esito terminale mostra la schermata di risultato — festa coi coriandoli al
// successo pieno, ramo onesto su parziale/errore (E-3).
//
// Le decisioni di presentazione vivono nei layer PURI `ScanFlowPresentation` (E-1) e
// `ScanSuccessPresentation` (E-3), testati; qui c'è solo il rendering SwiftUI e il
// cablaggio delle azioni, guardato `#if canImport(SwiftUI)` — lo strato
// compilato-ma-non-testato (L-COL-006). Il view-model arriva già cablato
// dall'`AppEnvironment` iniettato: nessun singleton nascosto.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct HomeView: View {
    @State private var vm: ScanViewModel
    @AppStorage(ThemePreference.storageKey) private var theme: ThemeChoice = .system
    @State private var showThemeSettings = false
    @State private var goToDashboard = false
    @State private var cancellation = CancellationToken()
    @State private var scanTask: Task<Void, Never>?
    // FSE-J4: la fase del ciclo di vita, osservata esplicitamente. Il ripristino al foreground
    // NON dipende più dal solo `.task` del primo appear (fragile al resume-da-sospensione).
    @Environment(\.scenePhase) private var scenePhase
    // FSE-J4: l'ultima fase SIGNIFICATIVA vista (gli `.inactive` transitori sono collassati),
    // così una transizione reale background→active arriva alla policy come tale.
    @State private var lastSignificantPhase: AppLifecyclePhase = .active
    // FSE-J4: marker persistito «stavo guardando i risultati», scritto verso background e
    // riletto al ritorno per atterrare sulla schermata esatta (dashboard o Home), mai su una
    // ri-scansione forzata. Sopravvive alla sospensione (e alla terminazione) via UserDefaults.
    @AppStorage(LifecycleMarker.wasViewingResultsKey) private var wasViewingResults = false
    // FSE-I1: il ripristino al lancio è UNA-TANTUM (cold relaunch), non a ogni comparsa
    // della Home: senza questo guardiano, tornare indietro dalla dashboard rientrerebbe
    // subito in dashboard (loop). Dopo il ripristino, la Home resta il «Ri-scansiona»
    // esplicito (tasto di scansione idle).
    @State private var didAttemptRestore = false
    // Conservato per costruire le schermate a valle (Dashboard) con lo stesso grafo
    // di dipendenze iniettato: nessun singleton nascosto.
    private let environment: AppEnvironment
    // P0-1: cache dei risultati posseduta SOPRA le view (da `App/`), propagata alla
    // dashboard e al report così sopravvive a navigazione e background.
    private let store: AnalysisResultsStore

    public init(environment: AppEnvironment, store: AnalysisResultsStore) {
        self.environment = environment
        self.store = store
        _vm = State(initialValue: ScanViewModel(environment: environment))
    }

    public var body: some View {
        screen
            .background(AuroraBrand.glow.ignoresSafeArea())
            .navigationTitle("Angavu")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .navigationDestination(isPresented: $goToDashboard) {
                DashboardView(environment: environment, store: store)
            }
            .sheet(isPresented: $showThemeSettings) { themeSheet }
            .task { restoreAtLaunchIfNeeded() }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .hapticFeedback(on: HomeScanPresentation(state: vm.state).kind) { _, new in
                switch new {
                case .completed: return .success
                case .failed: return .failure
                default: return nil
                }
            }
    }

    // MARK: Schermata — risultato terminale (E-3) o flusso a tasto unico (E-1/E-2)

    @ViewBuilder private var screen: some View {
        if let result = ScanSuccessPresentation.make(state: vm.state) {
            ScanResultScreen(
                result: result,
                onPrimary: { primaryAction(for: result) },
                onOpenSettings: openAppSettings
            )
        } else {
            ScanFlowScreen(
                flow: ScanFlowPresentation(state: vm.state),
                carousel: .angavu,
                onTap: startScan,
                onCancel: cancelScan
            )
        }
    }

    // MARK: Toolbar + tema

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // `.primaryAction` è cross-platform (trailing su iOS): il package è compilato
        // anche per macOS dal job `swift build`, quindi niente `.topBarTrailing`.
        ToolbarItem(placement: .primaryAction) {
            Button {
                showThemeSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Impostazioni tema")
        }
    }

    private var themeSheet: some View {
        NavigationStack {
            ThemeSettingsView(choice: $theme)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fatto") { showThemeSettings = false }
                    }
                }
        }
    }

    // MARK: Azioni

    private func primaryAction(for result: ScanSuccessPresentation) {
        if result.leadsToDashboard {
            goToDashboard = true
        } else {
            startScan() // "Riprova" dal ramo onesto di fallimento.
        }
    }

    /// FSE-I1 — Ripristino al lancio: se una scansione esiste già (indice persistito non
    /// vuoto), si atterra in dashboard SENZA forzare una nuova scansione unificata (il
    /// difetto del cold relaunch). Una-tantum e solo dallo stato `.idle`: dopo un ripristino
    /// tornare in Home mostra il tasto di scansione — il «Ri-scansiona» esplicito. Il
    /// ripristino NON avvia `run()`: la dashboard leggerà i numeri freschi dall'indice.
    private func restoreAtLaunchIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard case .idle = vm.state else { return }
        if LaunchRestoreCoordinator(environment: environment).decision() == .restore {
            goToDashboard = true
        }
    }

    /// FSE-J4 — Gestione esplicita del ciclo di vita. Mappa la fase SwiftUI, collassa
    /// l'`.inactive` transitorio (né vero background né vero ritorno), poi applica la
    /// `ScenePhaseRestorePolicy` alla transizione dall'ultima fase significativa. Così il
    /// ripristino al foreground non dipende dal solo `.task` del primo appear.
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        let mapped = AppLifecyclePhase(newPhase)
        guard mapped != .inactive else { return }
        let action = ScenePhaseRestorePolicy.action(
            from: lastSignificantPhase,
            to: mapped,
            indexedCount: LaunchRestoreCoordinator(environment: environment).indexedCount()
        )
        apply(action)
        lastSignificantPhase = mapped
    }

    /// FSE-J4 — Applica l'azione decisa dalla policy. Nessuna scansione forzata in nessun
    /// ramo: `startScan()` parte solo su tocco esplicito.
    private func apply(_ action: ScenePhaseAction) {
        switch action {
        case .persist:
            // Verso background: persisti il marker della schermata PRIMA che iOS possa
            // terminare l'app memory-heavy, così al ritorno si atterra dove si era.
            wasViewingResults = goToDashboard
        case .restore:
            // Ritorno reale dal background con dati indicizzati: riporta alla schermata
            // ESATTA (dashboard se si guardavano i risultati, altrimenti la Home idle —
            // mai una ri-scansione forzata).
            goToDashboard = wasViewingResults
        case .fresh:
            // Nessun dato indicizzato (primo avvio): il tasto di scansione, mai un restore
            // fantasma su una libreria non ancora scansionata.
            goToDashboard = false
        case .none:
            break
        }
    }

    private func startScan() {
        // P0-1: una nuova scansione ricostruisce l'indice → i numeri cambiano.
        // Invalidare la cache evita di mostrare cifre stantìe (manifesto: numeri veri).
        store.invalidateAll()
        // FSE-K2: il change token di libreria è catturato PRIMA della scansione — descrive
        // lo stato che i risultati rifletteranno; un cambio avvenuto DURANTE la scansione
        // ricade così nel delta al prossimo lancio (conservativo), mai perso. È persistito
        // a FINE scansione accanto a ogni `CategoryResultRecord` (write-through).
        let libraryToken = environment.changeTracker.currentToken()
        let token = CancellationToken()
        cancellation = token
        scanTask?.cancel()
        scanTask = Task {
            await vm.run(cancellation: token)
            // La scansione unificata ha già calcolato i numeri veri (fasi 2-3):
            // li mettiamo nella cache sopra le view così, toccando «È ora di fare
            // pulizia!», la dashboard è ISTANTANEA — nessuna seconda attesa
            // «Calcolo dei numeri veri…», nessun ricalcolo.
            if let figures = vm.figures {
                store.set(figures, for: .dashboard)
            }
            // FSE-F1: la scansione unificata ha già calcolato le review di categoria
            // (fasi dei rilevatori): le mettiamo nella cache sopra le view (chiavi
            // `.category(...)`) col timestamp per il badge di freschezza, così aprire
            // una categoria è ISTANTANEO — la `CategoryReviewView` trova il valore in
            // cache e non lancia mai una nuova composizione (nessun rilevatore al tap).
            let now = Date()
            for (category, data) in vm.categoryResults {
                store.set(data, for: .category(category.rawValue), at: now, libraryToken: libraryToken)
            }
        }
    }

    private func cancelScan() {
        cancellation.cancel()
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// FSE-J4 — Mappa la fase SwiftUI (`ScenePhase`) sulla fase di dominio pura, mantenendo
// SwiftUI fuori da AngavuDomain (altitudine). Ogni caso non-`.active`/`.background` (incluso
// l'`.inactive` e futuri casi) è trattato come transitorio (`.inactive`).
private extension AppLifecyclePhase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}
#endif
