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
    @State private var vm: DashboardViewModel
    // Conservato per costruire le schermate a valle (review categorie) con lo
    // stesso grafo di dipendenze iniettato: nessun singleton nascosto.
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        _vm = State(initialValue: DashboardViewModel(environment: environment))
    }

    private var presentation: DashboardPresentation {
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
                .foregroundStyle(AuroraBrand.gradient)
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
            ProgressView().progressViewStyle(.circular)
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: Spazio recuperabile (libreria vs device ORA)

    private func reclaimableCard(_ summary: DashboardPresentation.ReclaimableSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDashboardBytes(summary.deviceBytesNow))
                .font(.system(size: 44, weight: .bold, design: .rounded))
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
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Rivedi ed elimina — aggancio alle schermate di review (gate anteprima)

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rivedi ed elimina")
                .font(.headline)
            ForEach(CleanupCategory.allCases, id: \.self) { category in
                NavigationLink {
                    CategoryReviewView(environment: environment, category: category)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title).font(.headline)
                            Text(category.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: category.symbol)
                            .foregroundStyle(AuroraBrand.accentViola)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Comprimi video — libera spazio senza cancellare (opt-in)

    private var compressionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Libera spazio senza cancellare")
                .font(.headline)
            NavigationLink {
                CompressionView(environment: environment)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Comprimi video").font(.headline)
                        Text("Ricodifica HEVC on-device, opt-in: stima il risparmio "
                            + "prima di procedere, l'originale resta recuperabile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .foregroundStyle(AuroraBrand.accentViola)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Contatti e calendari — domini extra-foto (solo se le porte sono cablate)

    @ViewBuilder
    private var extraDomainsSection: some View {
        if let extra = environment.extraDomains {
            VStack(alignment: .leading, spacing: 12) {
                Text("Oltre le foto")
                    .font(.headline)
                NavigationLink {
                    ExtraPhotoDomainsView(ports: extra)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contatti e calendari").font(.headline)
                            Text("Contatti duplicati da fondere e sottoscrizioni "
                                + "calendario sospette — sempre su tua conferma.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "person.2")
                            .foregroundStyle(AuroraBrand.accentViola)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Report onesto — riepilogo numeri veri coi caveat

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il quadro completo")
                .font(.headline)
            NavigationLink {
                HonestReportView(environment: environment)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report onesto").font(.headline)
                        Text("Byte reali per categoria, spazio recuperabile e caveat "
                            + "iCloud — numeri veri, mai gonfiati.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(AuroraBrand.accentViola)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(pres.detail ?? "Errore sconosciuto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AuroraBrand.accentFucsia)
            }
            if pres.showsRetry {
                Button {
                    vm.load()
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

/// Riga di una categoria: conteggio, byte, marcatura della stima se presente.
private struct DashboardCategoryRow: View {
    let row: DashboardPresentation.CategoryRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                Text("\(row.count) elementi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.isEstimated
                    ? "~ \(formatDashboardBytes(row.totalBytes))"
                    : formatDashboardBytes(row.totalBytes))
                    .font(.body.monospacedDigit())
                if row.isEstimated {
                    Text("stima")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
