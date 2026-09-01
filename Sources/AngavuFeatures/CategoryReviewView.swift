// CategoryReviewView — la schermata «Rivedi ed elimina» (guscio UI, schermata 3).
//
// Presenta una categoria di pulizia (`CategoryReviewViewModel`, T-113): elenca gli
// elementi da tenere vs eliminabili e instrada OGNI eliminazione al gate
// d'anteprima obbligatorio della rete di sicurezza (`DeletionFlow`, T-050) — mai
// in autonomia, mai sui keep, mai un'anteprima vuota. La lista è alimentata dai
// dati VERI dell'indice (`CategoryReviewSource`): per gli screenshot è un filtro
// puro sul sottotipo indicizzato, zero API device-only.
//
// Le decisioni di presentazione vivono in `CategoryReviewPresentation` (puro,
// testato); qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` —
// l'unico strato compilato-ma-non-testato (L-COL-006). L'ambiente arriva iniettato
// dall'`AppEnvironment`: nessun singleton nascosto. L'esecuzione reale del delete
// (adapter della safety_net) è fuori scope qui: la conferma AUTORIZZA, la rete di
// sicurezza esegue. Le righe (`CategoryReviewRowView`/`RowThumbnailView`) vivono in
// `CategoryReviewView+Rows.swift`; le sezioni sono in una extension in fondo a
// questo file (tiene il corpo della struct sotto `type_body_length`).
#if canImport(SwiftUI)
import AngavuData
import AngavuDomain
import SwiftUI

/// Formatta una data di creazione in stile abbreviato locale (es. «14 mar 2024»),
/// o `nil` se la data è sconosciuta. Unica fonte del formato locale (come i byte).
private func formatReviewDate(_ date: Date?) -> String? {
    date?.formatted(date: .abbreviated, time: .omitted)
}

public struct CategoryReviewView: View {
    let environment: AppEnvironment
    let category: CleanupCategory
    // D-1: cache dei risultati posseduta SOPRA la view (da `App/`). Rientrando nella
    // categoria (navigazione back→avanti o ritorno dal background) il risultato si
    // riapplica senza ricalcolare; l'invalidazione (conferma eliminazione, scan,
    // cambio libreria) forza il ricalcolo. Niente più rianalisi da capo.
    let store: AnalysisResultsStore

    /// Fase di caricamento della sorgente. La review reale si legge dall'indice
    /// (può fallire): nessun blocco muto, nessuna lista vuota spacciata per «pulito».
    /// D-2: `.loading` porta un `AnalysisProgress?` — determinato quando il calcolo
    /// riporta X/N, `nil` (indeterminato onesto) quando non li espone.
    enum LoadPhase: Equatable {
        case loading(AnalysisProgress?)
        case loaded
        case failed(String)
    }

    @State var vm = CategoryReviewViewModel(review: CategoryReview(keepIds: [], removableIds: []))
    @State var loadPhase: LoadPhase = .loading(nil)
    /// FSE-J1 — Motivo dell'eliminazione REALE fallita (mai un falso successo). `nil`
    /// quando non c'è errore; presente → alert onesto.
    @State var deletionError: String?
    /// FSE-K3 — Vero se il contenuto mostrato è stato servito dalla cache (idratata o
    /// calcolata a monte) senza invocare il rilevatore; falso se composto ora al tap.
    /// Alimenta `loadedSourceIdentifier` (osservabile del Livello B).
    @State var servedFromCache = false

    public init(environment: AppEnvironment, category: CleanupCategory, store: AnalysisResultsStore) {
        self.environment = environment
        self.category = category
        self.store = store
    }

    /// Chiave di cache di questa categoria (id stabile = raw value dell'enum).
    var cacheKey: AnalysisResultKey { .category(category.rawValue) }

    var presentation: CategoryReviewPresentation {
        CategoryReviewPresentation(
            review: vm.review,
            flowState: vm.flow.state,
            title: category.title,
            subtitle: category.subtitle,
            assets: vm.assets,
            selection: vm.selection
        )
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
        .navigationTitle(category.title)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { actionBar }
        .alert(previewAlertTitle, isPresented: isPreviewing) {
            Button("Annulla", role: .cancel) { vm.cancelDeletion() }
            Button("Elimina", role: .destructive) {
                // FSE-J1: eliminazione REALE (PhotoKit → «Eliminati di recente»), non più solo il gate.
                // FSE-J2: cattura gli id proposti PRIMA della delete (il VM li toglie dalla selezione su success).
                let deleted = Set(vm.selectedRemovableIds)
                Task {
                    switch await vm.confirmAndDelete() {
                    case .success: store.pruneDeleted(ids: deleted) // J2: potatura chirurgica, non nuke
                    case .failed(let reason): deletionError = reason // errore onesto, mai un falso successo
                    case .cancelled: break // annullato dall'alert di sistema: nulla eliminato
                    }
                }
            }
        } message: {
            Text(presentation.safetyNote)
        }
        .alert("Eliminazione non riuscita", isPresented: showsDeletionError) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .task { await loadIfNeeded() }
        // FSE-K3: la ricomposizione in background (`.updating` → `.fresh`) riapplica il
        // valore ricomposto sul posto.
        .onChange(of: freshnessState) { old, new in freshnessDidChange(from: old, to: new) }
        // D-1: pull-to-refresh = «Ri-analizza» manuale. Invalida la cache e ricalcola
        // dai dati veri, ri-timbrando la freschezza.
        .refreshable { await loadIfNeeded(force: true) }
        .hapticFeedback(on: presentation.phase) { old, new in
            // Allerta tenue all'apertura dell'anteprima distruttiva (un solo owner).
            (old != .previewing && new == .previewing) ? .destructivePreview : nil
        }
    }
}

// MARK: - Sezioni e caricamento
//
// In extension (stesso file) per tenere il corpo della struct sotto il limite di
// leggibilità (type_body_length) senza cambiare comportamento — stesso pattern di
// DashboardView+Sections / CompressionView+Sections.
extension CategoryReviewView {

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(category.title)
                    .font(.largeTitle.weight(.bold))
                    // R-09 parsimonia: la cifra-hero vince, il titolo va a `.primary`.
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: category.symbol)
                    .foregroundStyle(AuroraBrand.accentViola)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            Text(category.subtitle)
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
        case .loading(let progress):
            loadingIndicator(progress)
        case .failed(let message):
            failedCard(message)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    var loadedContent: some View {
        let pres = presentation
        // FSE-K3: badge di freschezza — «in aggiornamento» (servita dalla persistenza,
        // delta in applicazione) o «da riscansionare» (non verificabile). Mai uno spinner
        // vuoto, mai un risultato stantìo spacciato per definitivo.
        if let badge = CategoryFreshnessPresentation.label(for: freshnessState) {
            freshnessBadge(badge, symbol: CategoryFreshnessPresentation.symbol(for: freshnessState))
        }
        if pres.phase == .confirmed {
            confirmedCard(pres)
        } else if pres.isEmpty {
            emptyCard
                .accessibilityIdentifier(loadedSourceIdentifier)
        } else {
            summaryCard(pres)
            if !pres.removableRows.isEmpty { rowsSection("Da eliminare", pres.removableRows) }
            if !pres.keepRows.isEmpty { rowsSection("Da tenere", pres.keepRows) }
        }
    }

    // MARK: Sezioni di righe

    func rowsSection(_ title: String, _ rows: [CategoryReviewPresentation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                // A-2: «seleziona tutto/niente» solo per la sezione dei removable
                // (i keep non sono selezionabili). Presente solo mentre si rivede.
                if presentation.phase == .reviewing, rows.contains(where: \.isSelectable) {
                    selectAllControl
                }
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.id) { row in
                    CategoryReviewRowView(
                        row: row,
                        formattedDate: formatReviewDate(row.creationDate),
                        onToggle: row.isSelectable ? { vm.toggleSelection(row.id) } : nil,
                        thumbnailProvider: environment.thumbnailProvider
                    )
                    if row.id != rows.last?.id { Divider() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        }
    }

    var selectAllControl: some View {
        let allSelected = presentation.selectedRemovableCount == presentation.removableCount
        return Button {
            if allSelected { vm.selectNone() } else { vm.selectAllRemovable() }
        } label: {
            Text(allSelected ? "Deseleziona tutto" : "Seleziona tutto")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
    }

    // MARK: Stato vuoto (niente da eliminare)

    var emptyCard: some View {
        ContentUnavailableView(
            "Niente da eliminare qui",
            systemImage: "checkmark.circle",
            description: Text("La tua libreria non contiene elementi in questa categoria. "
                + "Se hai appena concesso l'accesso, esegui prima un'analisi dalla Home.")
        )
    }

    // MARK: Conferma (eliminazione autorizzata → rete di sicurezza)

    func confirmedCard(_ pres: CategoryReviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(pres.confirmedCount == 1
                    ? "1 elemento pronto per l'eliminazione"
                    : "\(pres.confirmedCount) elementi pronti per l'eliminazione")
                    .font(.headline)
            } icon: {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(AuroraBrand.accentAzzurro)
                    .accessibilityHidden(true)
            }
            Text(pres.safetyNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                vm.cancelDeletion()
            } label: {
                Label("Rivedi di nuovo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Stato d'errore

    func failedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AuroraBrand.accentFucsia)
                    .accessibilityHidden(true)
            }
            Button {
                loadPhase = .loading(nil)
                Task { await loadIfNeeded(force: true) }
            } label: {
                Label("Riprova", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Barra d'azione (apre il gate d'anteprima)

    @ViewBuilder
    var actionBar: some View {
        if presentation.canRequestDeletion {
            // A-2: la CTA elimina i SELEZIONATI (non più tutto-o-niente), instradati
            // allo stesso gate d'anteprima. Disabilitata se non c'è selezione.
            Button {
                vm.presentDeletionPreviewForSelection()
            } label: {
                Text(deletionCTATitle)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AuroraBrand.gradient, in: .capsule)
                    .foregroundStyle(AuroraBrand.onGradient)
                    .opacity(presentation.hasSelection ? 1 : 0.5)
            }
            .disabled(!presentation.hasSelection)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    var deletionCTATitle: String {
        let count = presentation.selectedRemovableCount
        if count == 0 { return "Seleziona elementi da eliminare" }
        return count == 1 ? "Elimina 1 selezionato" : "Elimina \(count) selezionati"
    }

    // MARK: Anteprima come alert (gate obbligatorio)

    var previewAlertTitle: String {
        presentation.previewCount == 1
            ? "Eliminare 1 elemento?"
            : "Eliminare \(presentation.previewCount) elementi?"
    }

    /// Vero SOLO in fase `previewing`. Un alert iOS si chiude unicamente coi suoi
    /// pulsanti, ed entrambi (Annulla → `cancelDeletion`, Elimina → `confirmDeletion`)
    /// spostano già la fase fuori da `previewing`, così il `get` torna falso e
    /// l'alert si chiude. Il `set` è quindi un no-op: nessuna race di ordinamento
    /// tra l'azione del pulsante e la dismissal di sistema.
    var isPreviewing: Binding<Bool> {
        Binding(get: { presentation.phase == .previewing }, set: { _ in })
    }

    /// FSE-J1 — Vero quando c'è un errore di eliminazione da mostrare. Il `set` a `false`
    /// (OK / dismissal) azzera il motivo.
    var showsDeletionError: Binding<Bool> {
        Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
    }

}
#endif
