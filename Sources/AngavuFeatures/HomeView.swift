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

    private func startScan() {
        // P0-1: una nuova scansione ricostruisce l'indice → i numeri cambiano.
        // Invalidare la cache evita di mostrare cifre stantìe (manifesto: numeri veri).
        store.invalidateAll()
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
#endif
