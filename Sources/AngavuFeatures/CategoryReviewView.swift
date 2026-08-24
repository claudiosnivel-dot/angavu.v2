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
// sicurezza esegue.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

public struct CategoryReviewView: View {
    private let environment: AppEnvironment
    private let category: CleanupCategory

    /// Fase di caricamento della sorgente. La review reale si legge dall'indice
    /// (può fallire): nessun blocco muto, nessuna lista vuota spacciata per «pulito».
    private enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var vm = CategoryReviewViewModel(review: CategoryReview(keepIds: [], removableIds: []))
    @State private var loadPhase: LoadPhase = .loading

    public init(environment: AppEnvironment, category: CleanupCategory) {
        self.environment = environment
        self.category = category
    }

    private var presentation: CategoryReviewPresentation {
        CategoryReviewPresentation(
            review: vm.review,
            flowState: vm.flow.state,
            title: category.title,
            subtitle: category.subtitle
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
            Button("Elimina", role: .destructive) { vm.confirmDeletion() }
        } message: {
            Text(presentation.safetyNote)
        }
        .onAppear { loadIfNeeded() }
        .hapticFeedback(on: presentation.phase) { old, new in
            // Allerta tenue all'apertura dell'anteprima distruttiva (un solo owner).
            (old != .previewing && new == .previewing) ? .destructivePreview : nil
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(category.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AuroraBrand.gradient)
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
    private var content: some View {
        switch loadPhase {
        case .loading:
            ProgressView("Analisi della categoria…").progressViewStyle(.circular)
        case .failed(let message):
            failedCard(message)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let pres = presentation
        if pres.phase == .confirmed {
            confirmedCard(pres)
        } else if pres.isEmpty {
            emptyCard
        } else {
            summaryCard(pres)
            if !pres.removableRows.isEmpty { rowsSection("Da eliminare", pres.removableRows) }
            if !pres.keepRows.isEmpty { rowsSection("Da tenere", pres.keepRows) }
        }
    }

    // MARK: Riepilogo

    private func summaryCard(_ pres: CategoryReviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(pres.removableCount)")
                .auroraHeroNumber()
                .foregroundStyle(AuroraBrand.gradient)
            Text(pres.removableCount == 1 ? "elemento da eliminare" : "elementi da eliminare")
                .font(.headline)
                .foregroundStyle(.secondary)
            if pres.keepCount > 0 {
                Text("\(pres.keepCount) da tenere")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Label {
                Text(pres.safetyNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(AuroraBrand.accentAzzurro)
                    .accessibilityHidden(true)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Sezioni di righe

    private func rowsSection(_ title: String, _ rows: [CategoryReviewPresentation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(rows, id: \.id) { row in
                    CategoryReviewRowView(row: row)
                    if row.id != rows.last?.id { Divider() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: Stato vuoto (niente da eliminare)

    private var emptyCard: some View {
        ContentUnavailableView(
            "Niente da eliminare qui",
            systemImage: "checkmark.circle",
            description: Text("La tua libreria non contiene elementi in questa categoria. "
                + "Se hai appena concesso l'accesso, esegui prima un'analisi dalla Home.")
        )
    }

    // MARK: Conferma (eliminazione autorizzata → rete di sicurezza)

    private func confirmedCard(_ pres: CategoryReviewPresentation) -> some View {
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

    private func failedCard(_ message: String) -> some View {
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
                loadPhase = .loading
                loadIfNeeded(force: true)
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
    private var actionBar: some View {
        if presentation.canRequestDeletion {
            Button {
                vm.presentDeletionPreviewForAllRemovable()
            } label: {
                Text(presentation.removableCount == 1
                    ? "Elimina 1 elemento"
                    : "Elimina \(presentation.removableCount) elementi")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AuroraBrand.gradient, in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: Anteprima come alert (gate obbligatorio)

    private var previewAlertTitle: String {
        presentation.previewCount == 1
            ? "Eliminare 1 elemento?"
            : "Eliminare \(presentation.previewCount) elementi?"
    }

    /// Vero SOLO in fase `previewing`. Un alert iOS si chiude unicamente coi suoi
    /// pulsanti, ed entrambi (Annulla → `cancelDeletion`, Elimina → `confirmDeletion`)
    /// spostano già la fase fuori da `previewing`, così il `get` torna falso e
    /// l'alert si chiude. Il `set` è quindi un no-op: nessuna race di ordinamento
    /// tra l'azione del pulsante e la dismissal di sistema.
    private var isPreviewing: Binding<Bool> {
        Binding(get: { presentation.phase == .previewing }, set: { _ in })
    }

    // MARK: Caricamento della sorgente reale

    private func loadIfNeeded(force: Bool = false) {
        if !force, loadPhase == .loaded { return }
        do {
            let review = try CategoryReviewSource.review(for: category, from: environment)
            vm = CategoryReviewViewModel(review: review)
            loadPhase = .loaded
        } catch {
            loadPhase = .failed(String(describing: error))
        }
    }
}

/// Riga di review: id dell'asset e badge di disposizione (tenere / eliminabile).
private struct CategoryReviewRowView: View {
    let row: CategoryReviewPresentation.Row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(row.id)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 8)
        // VoiceOver: un solo elemento con etichetta UMANA — mai il `localIdentifier`
        // grezzo (che resta visibile a schermo), la disposizione come valore.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue)
    }

    private var symbol: String {
        switch row.disposition {
        case .keep: return "lock"
        case .removable: return "trash"
        }
    }

    private var label: String {
        switch row.disposition {
        case .keep: return "TIENI"
        case .removable: return "ELIMINABILE"
        }
    }

    private var tint: Color {
        switch row.disposition {
        case .keep: return AuroraBrand.accentAzzurro
        case .removable: return AuroraBrand.accentFucsia
        }
    }
}
#endif
