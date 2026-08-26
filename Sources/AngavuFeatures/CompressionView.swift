// CompressionView — la schermata «Comprimi video» (guscio UI), flusso a BATCH.
//
// B-2: dove vivono i ~106 GB di video del device-test, si comprime in blocco.
// Elenca i video VERI dell'indice (`CompressionCandidateSource`, byte reali) con
// MINIATURA (A-1, «mai alla cieca»), stima il risparmio aggregato sui più grandi
// (`BatchCompressionEstimator`, sempre marcato stima, cap dichiarato), lascia
// SELEZIONARE il sottoinsieme (opt-in: nulla preselezionato) e — solo dopo la
// conferma dell'anteprima della rete di sicurezza — comprime i selezionati con
// PROGRESSO DETERMINATO e ANNULLA, instradando OGNI originale a «Eliminati di
// recente» (mai un delete diretto, mai una perdita di dati).
//
// Le decisioni vivono nei layer puri (`BatchCompression*` nel Domain,
// `BatchCompressionPresentation`/`BatchCompressionViewModel` in Features, testati);
// qui c'è solo il rendering SwiftUI guardato `#if canImport(SwiftUI)` — l'unico
// strato compilato-ma-non-testato (L-COL-006). Miniature, stima on-device ed export
// reale sono device-only: compilati in CI, runtime dichiarato NON coperto. Le
// sezioni di rendering stanno in `CompressionView+Sections.swift`.
#if canImport(SwiftUI)
import AngavuDomain
import AngavuData
import SwiftUI

/// Formatta i byte in stile file (KB/MB/GB), rispettando la locale.
func formatCompressionBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

public struct CompressionView: View {
    let environment: AppEnvironment

    /// Fase di caricamento della lista candidati. La lettura dell'indice può
    /// fallire: nessun blocco muto, nessuna lista vuota spacciata per «nessun video».
    enum LoadPhase: Equatable {
        case loading
        case loaded([CompressionCandidate])
        case failed(String)
    }

    /// Tetto della stima: quanti video (i più grandi, già ordinati) leggere
    /// on-device per la stima. Limita il costo su librerie con migliaia di video
    /// (perf, no freeze); la copertura ridotta è DICHIARATA a schermo, mai silente.
    static let estimateCap = 100

    @State var vm: BatchCompressionViewModel
    @State var loadPhase: LoadPhase = .loading
    /// Vero mentre l'anteprima batch attende la conferma (rete di sicurezza).
    @State var pendingBatchConfirmation = false

    public init(environment: AppEnvironment) {
        self.environment = environment
        _vm = State(initialValue: BatchCompressionViewModel(exporter: environment.videoExporter))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle("Comprimi video")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Comprimere i video selezionati?", isPresented: $pendingBatchConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Comprimi e sostituisci", role: .destructive) { startBatch() }
        } message: {
            Text(BatchCompressionCopy.safetyNet)
        }
        .task { await loadIfNeeded() }
        .hapticFeedback(on: vm.phase) { _, new in
            // Onestà: si festeggia solo se qualcosa è stato davvero compresso.
            new == .done && (vm.run?.succeededCount ?? 0) > 0 ? .success : nil
        }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Comprimi video")
                    .font(.largeTitle.weight(.bold))
                    // R-09 parsimonia: la cifra-hero (stima) vince, il titolo va a `.primary`.
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundStyle(AuroraBrand.accentViola)
            }
            Text("Libera spazio senza cancellare: ricodifica HEVC on-device, opt-in, "
                + "numeri veri. Gli originali restano recuperabili dalla rete di sicurezza.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    // MARK: Contenuto per fase di caricamento

    @ViewBuilder
    var content: some View {
        switch loadPhase {
        case .loading:
            ProgressView("Lettura dei video…").progressViewStyle(.circular)
        case .failed(let message):
            indexFailedCard(message)
        case .loaded(let candidates):
            if candidates.isEmpty {
                noVideosCard
            } else {
                flowContent(candidates)
            }
        }
    }

    // MARK: Contenuto per fase del flusso batch

    @ViewBuilder
    func flowContent(_ candidates: [CompressionCandidate]) -> some View {
        switch vm.phase {
        case .selecting:
            selectingSection(candidates)
        case .running:
            runningSection
        case .done:
            doneSection
        }
    }

    // MARK: Binding del preset (ricalcola la stima al cambio, senza rifetch)

    var presetBinding: Binding<HEVCPreset> {
        Binding(
            get: { vm.preset },
            set: { newValue in
                vm.preset = newValue
                vm.reestimate()
            }
        )
    }

    // MARK: Azioni

    // La raccolta dei candidati (lettura indice video + byte per-asset via PhotoKit)
    // e la stima (durata/bitrate on-device) sono pesanti: girano FUORI dal main.
    // `loadIfNeeded` è @MainActor (metodo di View) e delega ai metodi non isolati
    // del VM / statici, tornando sul main solo per lo stato.
    @MainActor
    func loadIfNeeded(force: Bool = false) async {
        if !force, case .loaded = loadPhase { return }
        do {
            let candidates = try await CompressionView.loadCandidates(from: environment)
            vm.setCandidates(candidates)
            loadPhase = .loaded(candidates)
            await vm.computeEstimate(cap: Self.estimateCap, using: environment.videoSpecProvider)
        } catch {
            loadPhase = .failed(String(describing: error))
        }
    }

    /// Calcolo pesante dei candidati, ESPLICITAMENTE non isolato al main.
    nonisolated static func loadCandidates(from environment: AppEnvironment) async throws -> [CompressionCandidate] {
        try CompressionCandidateSource.candidates(from: environment)
    }

    /// Avvia la compressione dei selezionati dopo la conferma dell'anteprima batch.
    func startBatch() {
        Task { await vm.start(previewConfirmed: true) }
    }

    /// Ricomincia: torna alla selezione (nuova coda, consenso revocato).
    func resetBatch() {
        vm.reset()
    }
}
#endif
