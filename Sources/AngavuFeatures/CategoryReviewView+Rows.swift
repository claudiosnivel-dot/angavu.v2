// CategoryReviewView+Rows — sotto-componenti di riga della schermata di review.
//
// Estratti da `CategoryReviewView.swift` (guscio UI) per tenere il file principale
// sotto il limite di leggibilità (file_length) senza cambiare comportamento: solo
// SwiftUI, guardato `#if canImport(SwiftUI)`, strato compilato-ma-non-testato
// (L-COL-006). `internal` (non `private`) perché usati da `CategoryReviewView`, che
// vive in un altro file dello stesso modulo.
#if canImport(SwiftUI)
import AngavuData
import AngavuDomain
import SwiftUI

/// Riga di review: etichetta UMANA (tipo · data, A-3) + controllo di selezione per i
/// removable (A-2) o badge «TIENI» per i keep. Il `localIdentifier` grezzo non è più
/// mostrato: resta solo nel modello per la logica/accessibilità.
struct CategoryReviewRowView: View {
    let row: CategoryReviewPresentation.Row
    /// Data già formattata (dalla View, unica fonte del formato locale), o `nil`.
    let formattedDate: String?
    /// Azione di toggle selezione; `nil` per i keep (non selezionabili, protetti).
    let onToggle: (() -> Void)?
    /// A-1: provider di miniature reali (device-only); placeholder se non residente.
    let thumbnailProvider: any AssetThumbnailProviding

    var body: some View {
        // R-08: alle accessibility sizes il controllo di coda verrebbe compresso
        // contro il titolo; ViewThatFits lo porta sotto prima di comprimere. Stessi
        // accessibility modifier in entrambi i branch.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity
                Spacer(minLength: 12)
                trailing
            }
            VStack(alignment: .leading, spacing: 6) {
                identity
                trailing
            }
        }
        .padding(.vertical, 8)
        // VoiceOver: un solo elemento con etichetta UMANA (tipo + data) — mai il
        // `localIdentifier` grezzo. Valore = disposizione + stato di selezione.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(formattedDate: formattedDate))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
        .contentShape(Rectangle())
        .onTapGesture { onToggle?() }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            RowThumbnailView(
                provider: thumbnailProvider,
                id: row.id,
                placeholderSymbol: symbol,
                tint: tint
            )
            Text(row.displayTitle(formattedDate: formattedDate))
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if row.isSelectable {
            // Indicatore visivo; il toggle è gestito dal tap sull'intera riga (un solo
            // owner del gesto → niente doppio-toggle). Nascosto a VoiceOver: lo stato è
            // già nel trait/valore della riga.
            Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.isSelected ? AuroraBrand.accentFucsia : .secondary)
                .imageScale(.large)
                .accessibilityHidden(true)
        } else {
            Text("TIENI")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AuroraBrand.accentAzzurro)
                .lineLimit(1)
        }
    }

    /// Valore VoiceOver: disposizione + (per i selezionabili) stato di selezione.
    private var accessibilityValue: String {
        guard row.isSelectable else { return row.accessibilityValue }
        return row.isSelected
            ? "\(row.accessibilityValue), selezionato"
            : "\(row.accessibilityValue), non selezionato"
    }

    private var symbol: String {
        switch row.category {
        case .video?: return "video"
        case .screenshot?: return "camera.viewfinder"
        case .photo?, nil: return "photo"
        }
    }

    private var tint: Color {
        row.disposition == .keep ? AuroraBrand.accentAzzurro : AuroraBrand.accentFucsia
    }
}

/// A-1 — Miniatura reale di una riga, caricata async off-main. Placeholder (glifo di
/// categoria) finché non è pronta o quando l'originale è solo in iCloud (nil). Nessun
/// download di rete (il provider usa `isNetworkAccessAllowed=false`).
struct RowThumbnailView: View {
    let provider: any AssetThumbnailProviding
    let id: String
    let placeholderSymbol: String
    let tint: Color

    private static let side: CGFloat = 44
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholderSymbol)
                    .foregroundStyle(tint)
                    .imageScale(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // `.task(id:)` ricarica se la riga viene riusata per un altro asset (scroll).
        .task(id: id) {
            image = await provider.thumbnail(forLocalIdentifier: id, maxPixel: 120)
        }
        .accessibilityHidden(true)
    }
}
#endif
