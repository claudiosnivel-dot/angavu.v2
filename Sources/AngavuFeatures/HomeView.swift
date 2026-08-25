// HomeView — la schermata cardine dopo l'onboarding (guscio UI, mockup «Home»).
//
// Presenta il flusso di scansione (`ScanViewModel`, T-111) con TUTTI i controlli:
// avvia l'analisi, mostra l'avanzamento, la annulla (stop cooperativo, motore
// T-004), e ne dà un recap ONESTO — conteggio parziale dichiarato tale, errore con
// motivo esplicito e, se l'accesso è negato, la scorciatoia a Impostazioni. Da qui
// si raggiungono il tema in-app e la schermata "cosa NON facciamo".
//
// Le decisioni di presentazione vivono in `HomeScanPresentation` (puro, testato);
// qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` — l'unico
// strato compilato-ma-non-testato (L-COL-006). Il view-model arriva già cablato
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

    private var presentation: HomeScanPresentation {
        HomeScanPresentation(state: vm.state)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                statusCard
                if presentation.kind == .completed { dashboardLink }
                nonGoalsLink
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle("Angavu")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(isPresented: $showThemeSettings) { themeSheet }
        .hapticFeedback(on: presentation.kind) { _, new in
            switch new {
            case .completed: return .success
            case .failed: return .failure
            default: return nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Angavu")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
                .accessibilityAddTraits(.isHeader)
            Text("Numeri veri, sul tuo dispositivo.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    // MARK: Status card — dipende dalla classe di stato

    @ViewBuilder
    private var statusCard: some View {
        let pres = presentation
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(pres.title).font(.headline)
            } icon: {
                Image(systemName: statusSymbol(for: pres.kind))
                    .foregroundStyle(statusTint(for: pres.kind))
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)

            if let detail = pres.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = pres.progress {
                ProgressView(value: progress.fraction) {
                    Text("Analisi")
                } currentValueLabel: {
                    Text("\(progress.processed)/\(progress.total)").monospacedDigit()
                }
                .tint(AuroraBrand.accentViola)
            } else if pres.kind == .working {
                ProgressView().progressViewStyle(.circular)
            }

            if pres.offersOpenSettings {
                openSettingsButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private var openSettingsButton: some View {
        Button {
            openAppSettings()
        } label: {
            Label("Apri Impostazioni", systemImage: "gear")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }

    // MARK: Dashboard (numeri veri) — raggiungibile dal recap di scansione

    private var dashboardLink: some View {
        NavigationLink {
            DashboardView(environment: environment, store: store)
        } label: {
            Label("Vedi i numeri veri", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)
        }
        .foregroundStyle(AuroraBrand.accentAzzurro)
    }

    // MARK: Non-goals

    private var nonGoalsLink: some View {
        NavigationLink {
            NonGoalsView()
        } label: {
            Label("Cosa NON facciamo", systemImage: "xmark.seal")
                .font(.headline)
        }
        .foregroundStyle(AuroraBrand.accentFucsia)
    }

    // MARK: Barra d'azione in fondo

    @ViewBuilder
    private var actionBar: some View {
        let pres = presentation
        if pres.canCancel {
            Button(role: .cancel) {
                cancelScan()
            } label: {
                Text("Annulla")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        } else if pres.showsPrimaryAction {
            Button {
                startScan()
            } label: {
                Text(pres.primaryActionTitle)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AuroraBrand.gradient, in: .capsule)
                    .foregroundStyle(AuroraBrand.onGradient)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: Toolbar + tema

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // `.primaryAction` è cross-platform (trailing su iOS): il package è
        // compilato anche per macOS dal job `swift build`, quindi niente
        // `.topBarTrailing` (iOS-only).
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

    private func startScan() {
        // P0-1: una nuova scansione ricostruisce l'indice → i numeri cambiano.
        // Invalidare la cache evita di mostrare cifre stantìe (manifesto: numeri veri).
        store.invalidateAll()
        let token = CancellationToken()
        cancellation = token
        scanTask?.cancel()
        scanTask = Task { await vm.run(cancellation: token) }
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

    // MARK: Mappa di presentazione (icona/tinta per classe di stato)

    private func statusSymbol(for kind: HomeScanPresentation.Kind) -> String {
        switch kind {
        case .idle: return "sparkle.magnifyingglass"
        case .working: return "hourglass"
        case .completed: return "checkmark.circle"
        case .cancelled: return "stop.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func statusTint(for kind: HomeScanPresentation.Kind) -> Color {
        switch kind {
        case .idle, .working: return AuroraBrand.accentViola
        case .completed: return AuroraBrand.accentAzzurro
        case .cancelled: return .secondary
        case .failed: return AuroraBrand.accentFucsia
        }
    }
}
#endif
