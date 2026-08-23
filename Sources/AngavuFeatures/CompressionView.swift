// CompressionView — la schermata «Comprimi video» (guscio UI).
//
// Presenta il flusso di compressione cablato (`CompressionViewModel`, T-116):
// elenca i video VERI dell'indice (`CompressionCandidateSource`, byte reali),
// stima il risparmio on-device (mai fabbricato), richiede il consenso opt-in
// esplicito e — solo dopo la conferma dell'anteprima della rete di sicurezza —
// ricodifica in HEVC instradando l'originale a «Eliminati di recente» (mai un
// delete diretto, mai una perdita di dati).
//
// Le decisioni di presentazione vivono in `CompressionPresentation` (puro,
// testato); qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` —
// l'unico strato compilato-ma-non-testato (L-COL-006). L'ambiente arriva iniettato
// dall'`AppEnvironment`: exporter e lettore di spec dietro i port, nessun singleton
// nascosto. La stima (durata/bitrate) e l'export reale sono device-only: compilati
// in CI, runtime non coperto — dichiarato apertamente. Le sezioni di rendering
// stanno in `CompressionView+Sections.swift` (una sola type, spezzata per leggibilità).
#if canImport(SwiftUI)
import AngavuDomain
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

    @State var vm: CompressionViewModel
    @State var loadPhase: LoadPhase = .loading
    @State var selected: CompressionCandidate?
    @State var preset: HEVCPreset = .balanced
    @State var pendingConfirmation: CompressionCandidate?
    /// Avviso onesto quando la spec on-device non è leggibile (niente stima finta).
    @State var specNotice: String?
    @State var cancellation = CancellationToken()

    public init(environment: AppEnvironment) {
        self.environment = environment
        _vm = State(initialValue: CompressionViewModel(exporter: environment.videoExporter))
    }

    var presentation: CompressionPresentation {
        CompressionPresentation(state: vm.state)
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
        .alert("Sostituire l'originale?", isPresented: confirmationBinding) {
            Button("Annulla", role: .cancel) { pendingConfirmation = nil }
            Button("Comprimi e sostituisci", role: .destructive) { startCompression() }
        } message: {
            Text(CompressionPresentation.safetyNetText)
        }
        .onAppear { loadIfNeeded() }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Comprimi video")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AuroraBrand.gradient)
            } icon: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundStyle(AuroraBrand.accentViola)
            }
            Text("Libera spazio senza cancellare: ricodifica HEVC on-device, opt-in, "
                + "numeri veri. L'originale resta recuperabile dalla rete di sicurezza.")
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
            ProgressView().progressViewStyle(.circular)
        case .failed(let message):
            indexFailedCard(message)
        case .loaded(let candidates):
            flowContent(candidates)
        }
    }

    // MARK: Contenuto per fase del flusso di compressione

    @ViewBuilder
    func flowContent(_ candidates: [CompressionCandidate]) -> some View {
        let pres = presentation
        switch pres.phase {
        case .idle:
            if candidates.isEmpty {
                noVideosCard
            } else {
                presetPicker
                candidateList(candidates)
            }
        case .estimated:
            estimateCard(pres)
        case .consented:
            consentedCard(pres)
        case .working:
            workingCard(pres)
        case .done:
            doneCard(pres)
        case .cancelled:
            terminalCard(pres, symbol: "xmark.circle", tint: AuroraBrand.accentBlu)
        case .failed:
            terminalCard(pres, symbol: "exclamationmark.triangle", tint: AuroraBrand.accentFucsia, retry: true)
        }
    }

    // MARK: Binding dell'anteprima obbligatoria

    /// Vero SOLO quando c'è una compressione in attesa di conferma. L'alert si
    /// chiude coi suoi pulsanti (entrambi azzerano `pendingConfirmation`), quindi il
    /// `set` è un no-op: nessuna race tra l'azione e la dismissal di sistema.
    var confirmationBinding: Binding<Bool> {
        Binding(get: { pendingConfirmation != nil }, set: { _ in })
    }

    // MARK: Azioni

    func loadIfNeeded(force: Bool = false) {
        if !force, case .loaded = loadPhase { return }
        do {
            let candidates = try CompressionCandidateSource.candidates(from: environment)
            loadPhase = .loaded(candidates)
        } catch {
            loadPhase = .failed(String(describing: error))
        }
    }

    /// Legge la spec on-device (durata/bitrate) e calcola la stima. Se la spec non è
    /// disponibile, mostra un avviso onesto — mai una stima inventata.
    func estimate(for candidate: CompressionCandidate) {
        selected = candidate
        specNotice = nil
        Task {
            let spec = await environment.videoSpecProvider.videoSpec(
                forLocalIdentifier: candidate.id,
                originalBytes: candidate.originalBytes
            )
            guard let spec else {
                specNotice = "Non riesco a leggere durata/bitrate di questo video "
                    + "sul dispositivo: nessuna stima mostrata (non ne invento una)."
                return
            }
            vm.estimate(spec: spec, preset: preset)
        }
    }

    func grantConsent() {
        guard let candidate = selected else { return }
        vm.grantConsent(for: [candidate.id])
    }

    func startCompression() {
        guard let candidate = pendingConfirmation else { return }
        pendingConfirmation = nil
        cancellation = CancellationToken()
        Task {
            await vm.compress(
                originalId: candidate.id,
                preset: preset,
                exportVerifiedIntegral: true,
                previewConfirmed: true,
                cancellation: cancellation
            )
        }
    }

    /// Ricomincia da capo: nuovo view-model (stato `idle`, consenso azzerato).
    func reset() {
        vm = CompressionViewModel(exporter: environment.videoExporter)
        selected = nil
        specNotice = nil
        pendingConfirmation = nil
        cancellation = CancellationToken()
    }
}
#endif
