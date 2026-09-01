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
    // FSE-K3: il ripristino dei risultati (idratazione + delta del change token +
    // ricomposizione delle sole categorie toccate) gira in un task cancellabile: una
    // nuova scansione lo annulla (i suoi risultati rimpiazzeranno tutto).
    @State private var restoreTask: Task<Void, Never>?
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
    /// FSE-K3: PRIMA di navigare lo store è IDRATATO dai risultati persistiti (le categorie
    /// sono istantanee, 0 rilevatori), poi in background si applica il delta del change token.
    private func restoreAtLaunchIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard case .idle = vm.state else { return }
        guard LaunchRestoreCoordinator(environment: environment).decision() == .restore else { return }
        restoreTask?.cancel()
        restoreTask = Task { await restorePersistedResults(thenNavigate: true) }
    }

    /// FSE-K3 — Il fix del ripristino, in tre passi (`RestoreHydrationCoordinator`):
    ///  1. idratazione dalla persistenza (lettura dell'indice OFF-main, idratazione sul
    ///     main) PRIMA di navigare: ogni categoria persistita è servita subito, `.updating`;
    ///  2. piano di validità col change token (persistenza + delta PhotoKit, off-main) →
    ///     `.serve` diventa `.fresh`, `.fullRescan` diventa un invito dichiarato;
    ///  3. ricomposizione delle SOLE categorie toccate dal delta (una invocazione del
    ///     rispettivo rilevatore, off-main), ripersistite col token corrente.
    /// Un errore di lettura lascia la categoria non idratata: si ricompone al tap, come
    /// prima di K3 — mai un risultato inventato. Nessuna scansione parte da qui.
    private func restorePersistedResults(thenNavigate: Bool) async {
        let coordinator = RestoreHydrationCoordinator(store: store, environment: environment)
        let assetsById = (try? await RestoreHydrationCoordinator.readAssetsByIdOffMain(from: environment)) ?? [:]
        _ = try? coordinator.hydrate(assetsById: assetsById)
        if thenNavigate { goToDashboard = true }
        guard !Task.isCancelled,
              let plan = try? await RestoreHydrationCoordinator.planOffMain(store: store, environment: environment)
        else { return }
        coordinator.apply(plan)
        await coordinator.recompose(plan)
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
            // mai una ri-scansione forzata). FSE-K3: se nel frattempo lo store è rimasto
            // vuoto (ricreato), lo si idrata dalla persistenza senza cambiare schermata.
            goToDashboard = wasViewingResults
            if store.isEmpty, case .idle = vm.state {
                restoreTask?.cancel()
                restoreTask = Task { await restorePersistedResults(thenNavigate: false) }
            }
        case .fresh:
            // Nessun dato indicizzato (primo avvio): il tasto di scansione, mai un restore
            // fantasma su una libreria non ancora scansionata.
            goToDashboard = false
        case .none:
            break
        }
    }

    private func startScan() {
        // FSE-K3: NIENTE `invalidateAll()` cieco all'avvio (svuotava anche la persistenza
        // K1: un annullamento a metà cancellava i risultati validi della scansione
        // precedente). Il commit avviene SOLO a scansione completata
        // (`ScanResultsCommit`): rimpiazza le categorie raggiunte, invalida quelle il cui
        // rilevatore è fallito, aggiorna gli aggregati. Un ripristino in corso è annullato:
        // la nuova scansione rimpiazzerà tutto.
        restoreTask?.cancel()
        // FSE-K2: il change token di libreria è catturato PRIMA della scansione — descrive
        // lo stato che i risultati rifletteranno; un cambio avvenuto DURANTE la scansione
        // ricade così nel delta al prossimo lancio (conservativo), mai perso. È persistito
        // a FINE scansione accanto a ogni `CategoryResultRecord` (write-through).
        let libraryToken = environment.changeTracker.currentToken()
        let token = CancellationToken()
        cancellation = token
        scanTask?.cancel()
        scanTask = Task {
            let outcome = await vm.run(cancellation: token)
            // La scansione unificata ha già calcolato i numeri veri (fasi 2-3) e le review
            // di categoria (FSE-F1): a esito `completed` entrano nella cache sopra le view
            // (write-through col token, timbro di freschezza) così dashboard e categorie
            // sono ISTANTANEE — nessun ricalcolo, nessun rilevatore al tap. Su
            // `cancelled`/`failed` nulla è scritto: memoria e persistenza precedenti intatte.
            ScanResultsCommit.apply(
                state: outcome,
                figures: vm.figures,
                categoryResults: vm.categoryResults,
                into: store,
                libraryToken: libraryToken
            )
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
