// DashboardView+Sections — sezioni di navigazione della Dashboard «Numeri veri».
//
// Estensione di `DashboardView` (guscio UI): solo SwiftUI, guardata
// `#if canImport(SwiftUI)`. Separata dal core (`DashboardView.swift`) per tenere il
// corpo della type sotto il limite di leggibilità (type_body_length) senza cambiare
// il comportamento; nessuna logica — le decisioni stanno in `DashboardPresentation`
// (puro, testato). Strato compilato-ma-non-testato (L-COL-006). Ogni sezione naviga
// a una schermata a valle conservando l'`AppEnvironment` iniettato: nessun singleton.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

extension DashboardView {

    // MARK: Rivedi ed elimina — aggancio alle schermate di review (gate anteprima)

    var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rivedi ed elimina")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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
                            .accessibilityHidden(true)
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

    var compressionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Libera spazio senza cancellare")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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
                        .accessibilityHidden(true)
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
    var extraDomainsSection: some View {
        if let extra = environment.extraDomains {
            VStack(alignment: .leading, spacing: 12) {
                Text("Oltre le foto")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
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
                            .accessibilityHidden(true)
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

    var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il quadro completo")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
