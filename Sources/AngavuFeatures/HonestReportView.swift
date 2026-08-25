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
    // R-11: la transizione di fase idle→ready→failed è animata (dissolvenza) ma
    // SEMPRE gated su Reduce Motion, con equivalente statico (parità informativa:
    // cambia solo il crossfade, mai il contenuto). Stesso idioma di R-06/ContentView.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .animation(reduceMotion ? nil : .easeInOut, value: presentation.kind)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle("Report onesto")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Carica una sola volta alla comparsa, FUORI dal main thread (`.task`):
            // la risoluzione byte per-asset non deve bloccare la UI. «Riprova» ricompone.
            if case .idle = vm.state { await vm.load() }
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
            ProgressView("Calcolo del report…")
                .progressViewStyle(.circular)
                .transition(.opacity)
        case .ready:
            // I sottoblocchi condividono la stessa dissolvenza: entrano/escono come
            // un gruppo quando lo stato cambia (gated su Reduce Motion a monte).
            if let hero = pres.hero { heroHeader(hero).transition(.opacity) }
            if pres.showsPartialBanner {
                partialBanner(invitesFullAccess: pres.invitesFullAccess).transition(.opacity)
            }
            categoriesList(pres.categoryRows).transition(.opacity)
            if let reclaimable = pres.reclaimable { reclaimableCard(reclaimable).transition(.opacity) }
        case .failed:
            failedCard(pres).transition(.opacity)
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
        // R-10: un solo elemento VoiceOver con label parlata dal layer puro — mai
        // il "~" visivo (letto "tilde"): la stima è nominata "Stima" a voce.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(hero.accessibilityLabel(formattedBytes: formatReportBytes(hero.bytes)))
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
                .accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: 10) {
            // Cifra device SOLO se la residenza è determinabile; altrimenti caveat,
            // mai un numero fabbricato (P0-3, manifesto).
            if summary.deviceSpaceIsIndeterminate {
                Text("Spazio sul telefono: non determinabile ora")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatReportBytes(summary.deviceBytesNow))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("liberabili sul telefono ora")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(formatReportBytes(summary.deviceBytesNow)) liberabili sul telefono ora")
            }

            // P0-4: lo "spazio in libreria" (include iCloud) come riga separata ed
            // etichettata, mai spacciato per spazio-telefono.
            HStack(alignment: .firstTextBaseline) {
                Text("Spazio in libreria (include iCloud)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(formatReportBytes(summary.libraryBytes))
                    .font(.footnote.monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spazio in libreria, include iCloud")
            .accessibilityValue(formatReportBytes(summary.libraryBytes))

            if summary.iCloudCaveat {
                Label {
                    Text("Parte degli originali è in iCloud. Eliminando liberi la libreria, "
                        + "non subito lo spazio sul telefono.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(AuroraBrand.accentBlu)
                        .accessibilityHidden(true)
                }
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
                    .accessibilityHidden(true)
            }
            if pres.showsRetry {
                Button {
                    Task { await vm.load() }
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
        // dal layer puro — non i frammenti che i figli produrrebbero.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue(formattedBytes: formatReportBytes(row.totalBytes)))
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
                ? "~ \(formatReportBytes(row.totalBytes))"
                : formatReportBytes(row.totalBytes))
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
