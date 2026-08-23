// HonestReportView — il report onesto cablato (guscio UI, schermata 6).
//
// Presenta il report onesto sui dati veri (`HonestReportViewModel`, T-114): la
// cifra-hero (esatta SOLO quando nulla è stimato, altrimenti marcata come stima),
// le righe per categoria (stima marcata), lo spazio recuperabile con la distinzione
// libreria vs device ORA (caveat iCloud), il banner del conteggio parziale con
// l'invito all'accesso completo, e lo stato d'errore con motivo esplicito +
// "Riprova". Numeri veri coi caveat, mai un totale gonfiato (T-102).
//
// Le decisioni di presentazione vivono in `HonestReportPresentation` (puro, testato);
// qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` — l'unico
// strato compilato-ma-non-testato (L-COL-006). Il view-model arriva dall'`AppEnvironment`
// iniettato: nessun singleton nascosto.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Formatta i byte in stile file (KB/MB/GB), rispettando la locale.
private func formatReportBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

/// Schermata del report onesto, cablata sui dati veri.
public struct HonestReportView: View {
    @State private var vm: HonestReportViewModel

    public init(environment: AppEnvironment) {
        _vm = State(initialValue: HonestReportViewModel(environment: environment))
    }

    private var presentation: HonestReportPresentation {
        HonestReportPresentation(state: vm.state)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle("Report onesto")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            // Carica una sola volta alla comparsa; «Riprova» ricompone.
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
            if let hero = pres.hero { heroHeader(hero) }
            if pres.showsPartialBanner { partialBanner(invitesFullAccess: pres.invitesFullAccess) }
            categoriesList(pres.categoryRows)
            if let reclaimable = pres.reclaimable { reclaimableCard(reclaimable) }
        case .failed:
            failedCard(pres)
        }
    }

    // MARK: Cifra-hero (esatta o marcata come stima)

    private func heroHeader(_ hero: HonestReportPresentation.Hero) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if hero.isExact {
                Text(formatReportBytes(hero.bytes))
                    .auroraHeroNumber()
                    .foregroundStyle(AuroraBrand.gradient)
                Text("recuperabili")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Text("~ \(formatReportBytes(hero.bytes))")
                    .auroraHeroNumber()
                    .foregroundStyle(AuroraBrand.gradient)
                Text("stima (parte dei byte non è misurata con precisione)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    // MARK: Banner conteggio parziale (accesso limited)

    private func partialBanner(invitesFullAccess: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conteggio parziale")
                    .font(.headline)
                if invitesFullAccess {
                    Text("Hai concesso l'accesso solo ad alcune foto. Abilita l'accesso completo per numeri completi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(AuroraBrand.accentAzzurro)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: Righe per categoria

    private func categoriesList(_ rows: [HonestReportPresentation.CategoryRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.category) { row in
                HonestReportCategoryRow(row: row)
            }
        }
    }

    // MARK: Spazio recuperabile (libreria vs device ORA) + caveat iCloud

    private func reclaimableCard(_ summary: HonestReportPresentation.ReclaimableSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatReportBytes(summary.deviceBytesNow))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text("liberabili sul telefono ora")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if summary.iCloudCaveat {
                Label {
                    Text("In libreria \(formatReportBytes(summary.libraryBytes)): parte è in iCloud. "
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

    // MARK: Stato d'errore

    private func failedCard(_ pres: HonestReportPresentation) -> some View {
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

/// Riga di una categoria: conteggio, byte, e marca della stima se presente.
private struct HonestReportCategoryRow: View {
    let row: HonestReportPresentation.CategoryRow

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
                    ? "~ \(formatReportBytes(row.totalBytes))"
                    : formatReportBytes(row.totalBytes))
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
