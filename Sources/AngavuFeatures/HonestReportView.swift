// HonestReportView — il report onesto (11-ui-shell.md, T-102).
//
// Numeri veri con i caveat, mai un totale gonfiato: se c'è una porzione stimata
// non si mostra un unico numero "esatto"; il caveat iCloud e il conteggio
// parziale (accesso limited) sono dichiarati apertamente. Contenuto dominio puro
// (`HonestReport`); qui solo presentazione. Fuori dai target_tests (out_of_scope).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Formatta i byte in stile file (KB/MB/GB), rispettando la locale.
private func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

/// Schermata del report onesto.
public struct HonestReportView: View {
    private let report: HonestReport

    public init(report: HonestReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                totalHeader
                if report.countsArePartial { partialBanner }
                categoriesList
                if report.iCloudCaveat { iCloudCaveatNote }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
    }

    // La cifra-hero: un totale "esatto" SOLO quando nulla è stimato; altrimenti
    // si mostra la stima marcata come tale (mai spacciata per esatto).
    private var totalHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let exact = report.singleExactTotalBytes {
                Text(formatBytes(exact))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AuroraBrand.gradient)
                Text("recuperabili")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Text("~ \(formatBytes(report.totalExactBytes + report.totalEstimatedBytes))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AuroraBrand.gradient)
                Text("stima (parte dei byte non è misurata con precisione)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    private var partialBanner: some View {
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
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(report.categories, id: \.category) { item in
                CategoryReportRow(item: item)
            }
        }
    }

    private var iCloudCaveatNote: some View {
        Label {
            Text("Parte dello spazio è in iCloud: eliminando liberi la libreria, non subito lo spazio sul telefono.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "icloud")
                .foregroundStyle(AuroraBrand.accentBlu)
        }
    }
}

/// Riga di una categoria: conteggio, byte, e marcatura della stima se presente.
private struct CategoryReportRow: View {
    let item: CategoryBytes

    private var title: String {
        switch item.category {
        case .photo: return "Foto"
        case .video: return "Video"
        case .screenshot: return "Screenshot"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text("\(item.count) elementi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.hasEstimatedPortion ? "~ \(formatBytes(item.totalBytes))" : formatBytes(item.totalBytes))
                    .font(.body.monospacedDigit())
                if item.hasEstimatedPortion {
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
