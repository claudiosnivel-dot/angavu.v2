// CategoryReviewView+Summary — riepilogo della categoria e badge di freschezza.
//
// Estratto da `CategoryReviewView.swift` (guscio UI) per tenere il file principale
// sotto il limite di leggibilità (file_length) — stesso idioma di
// `CategoryReviewView+Rows` / `+Loading`. Solo SwiftUI, guardato `#if canImport(SwiftUI)`;
// il copy del badge FSE-K3 vive nel layer puro (`CategoryFreshnessPresentation`,
// testato). Strato compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import SwiftUI

extension CategoryReviewView {

    // MARK: Riepilogo

    /// FSE-K3 — Badge onesto dello stato di freschezza (copy dal layer puro).
    func freshnessBadge(_ text: String, symbol: String?) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol ?? "clock.arrow.circlepath")
                .foregroundStyle(AuroraBrand.accentAzzurro)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier(freshnessState == .updating
            ? "category.review.freshness.updating"
            : "category.review.freshness.needsFullRescan")
    }

    func summaryCard(_ pres: CategoryReviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(pres.removableCount)")
                .auroraHeroNumber()
                .foregroundStyle(AuroraBrand.gradient)
                // FSE-K3: la cifra-hero dichiara la provenienza (cache vs rilevatore) al
                // Livello B; il valore è letto dal test per il confronto fra i lanci.
                .accessibilityIdentifier(loadedSourceIdentifier)
            Text(pres.removableCount == 1 ? "elemento da eliminare" : "elementi da eliminare")
                .font(.headline)
                .foregroundStyle(.secondary)
            if pres.keepCount > 0 {
                Text("\(pres.keepCount) da tenere")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // D-1: badge di freschezza — dichiara quando i dati sono stati calcolati,
            // così un numero cachato non è mai spacciato per appena letto. Assente se
            // non tracciato (categoria non ancora timbrata).
            if let freshness = freshnessLabel {
                Label {
                    Text(freshness)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.top, 2)
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
}
#endif
