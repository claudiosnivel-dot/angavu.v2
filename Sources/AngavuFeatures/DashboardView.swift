// DashboardView — la schermata «Numeri veri» (guscio UI, schermata 2).
//
// Presenta la dashboard cablata coi dati veri (`DashboardViewModel`, T-112): righe
// per categoria coi byte reali (exact/estimated SEPARATI, la stima marcata), spazio
// recuperabile con la distinzione libreria vs device ORA (caveat iCloud), banner
// accesso limited col totale dichiarato parziale, e lo stato d'errore con motivo
// esplicito + "Riprova". Nessun numero gonfiato.
//
// Le decisioni di presentazione vivono in `DashboardPresentation` (puro, testato);
// qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` — l'unico
// strato compilato-ma-non-testato (L-COL-006). Il view-model arriva già cablato
// dall'`AppEnvironment` iniettato: nessun singleton nascosto.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Formatta i byte in stile file (KB/MB/GB), rispettando la locale.
private func formatDashboardBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

public struct DashboardView: View {
    @State var vm: DashboardViewModel
    // Conservato per costruire le schermate a valle (review categorie) con lo
    // stesso grafo di dipendenze iniettato: nessun singleton nascosto. Interno
    // (non private) così le sezioni in `DashboardView+Sections.swift` vi accedono.
    let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        _vm = State(initialValue: DashboardViewModel(environment: environment))
    }

    var presentation: DashboardPresentation {
        DashboardPresentation(state: vm.state)
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
        .navigationTitle("Numeri veri")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            // Carica una sola volta alla comparsa; il pull di «Riprova» ricarica.
            if case .idle = vm.state { vm.load() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.largeTitle.weight(.bold))
                // R-09 parsimonia: un solo gradiente per schermata → la cifra-hero
                // vince, il titolo passa al colore di testo primario.
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let detail = presentation.detail, presentation.kind != .failed {
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    // MARK: Contenuto per classe di stato

    @ViewBuilder
    private var content: some View {
        let pres = presentation
        switch pres.kind {
        case .idle:
            ProgressView("Calcolo dei numeri veri…").progressViewStyle(.circular)
        case .ready:
            if pres.showsLimitedBanner { limitedBanner }
            if let reclaimable = pres.reclaimable { reclaimableCard(reclaimable) }
            categoriesList(pres.categoryRows)
            cleanupSection
            compressionSection
            extraDomainsSection
            reportSection
        case .failed:
            failedCard(pres)
        }
    }

    // MARK: Banner accesso limited

    private var limitedBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conteggio parziale")
                    .font(.headline)
                Text("Hai concesso l'accesso solo ad alcune foto. Abilita l'accesso completo per numeri completi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(AuroraBrand.accentAzzurro)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: Spazio recuperabile (libreria vs device ORA)

    private func reclaimableCard(_ summary: DashboardPresentation.ReclaimableSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDashboardBytes(summary.deviceBytesNow))
                .auroraHeroNumber()
                .foregroundStyle(AuroraBrand.gradient)
            Text("liberabili sul telefono ora")
                .font(.headline)
                .foregroundStyle(.secondary)
            if summary.iCloudCaveat {
                Label {
                    Text("In libreria \(formatDashboardBytes(summary.libraryBytes)): parte è in iCloud. "
                        + "Eliminando liberi la libreria, non subito lo spazio sul telefono.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(AuroraBrand.accentBlu)
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Righe per categoria

    private func categoriesList(_ rows: [DashboardPresentation.CategoryRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.category) { row in
                DashboardCategoryRow(row: row)
            }
        }
    }

    // MARK: Stato d'errore

    private func failedCard(_ pres: DashboardPresentation) -> some View {
        ContentUnavailableView {
            Label("Numeri non disponibili", systemImage: "exclamationmark.triangle")
        } description: {
            Text(pres.detail ?? "Errore sconosciuto.")
        } actions: {
            if pres.showsRetry {
                Button {
                    vm.load()
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Riga di una categoria: conteggio, byte, marcatura della stima se presente.
private struct DashboardCategoryRow: View {
    let row: DashboardPresentation.CategoryRow

    var body: some View {
        // R-08: alle accessibility sizes il layout a due colonne si comprime;
        // ViewThatFits ripiega su una colonna (valore sotto il titolo) prima di
        // troncare. Stessi accessibility modifier in entrambi i branch.
        ViewThatFits(in: .horizontal) {
            HStack {
                titleColumn
                Spacer(minLength: 12)
                valueColumn
            }
            VStack(alignment: .leading, spacing: 4) {
                titleColumn
                valueColumn
            }
        }
        .padding(.vertical, 4)
        // VoiceOver: un solo elemento leggibile (titolo + conteggio/byte/stima),
        // dal layer puro — non i 3-4 frammenti che i figli produrrebbero.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue(formattedBytes: formatDashboardBytes(row.totalBytes)))
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).font(.headline)
                .lineLimit(2)
                .allowsTightening(true)
            Text("\(row.count) elementi")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var valueColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.isEstimated
                ? "~ \(formatDashboardBytes(row.totalBytes))"
                : formatDashboardBytes(row.totalBytes))
                .font(.body.monospacedDigit())
                .lineLimit(1)
            if row.isEstimated {
                Text("stima")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
