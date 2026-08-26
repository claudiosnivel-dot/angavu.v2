// E-4 (resa) / E-2 — Carosello "leggi mentre aspetti" nella metà superiore.
//
// Mentre la scansione è in corso, la metà superiore ospita il carosello: manifesto
// Angavu + curiosità sullo spazio (contenuto = DATI puri `ScanCarouselContent`, T-100
// idiom). Swipe manuale = default (page indicator, ogni slide un elemento VoiceOver).
// L'auto-avanzamento è LENTO e LEGGERO, ed è DISATTIVATO con Reduce Motion o VoiceOver
// attivi (mai un peso). Le curiosità mostrano il marchio "approssimativo" (manifesto:
// numeri veri — mai un ordine di grandezza spacciato per esatto). View-level (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import Combine
import Foundation
import SwiftUI

struct ScanCarouselView: View {
    let content: ScanCarouselContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var index = 0

    // Un solo timer per istanza: l'avanzamento è gated NEL gestore (nessun timer
    // ricreato a ogni render). ~7 s = lento, come da piano ("mai un peso").
    private let ticker = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        pagedTabView
            .onReceive(ticker) { _ in
                guard !reduceMotion, !voiceOver else { return }
                advance()
            }
    }

    private var pagedTabView: some View {
        TabView(selection: $index) {
            ForEach(Array(content.slides.enumerated()), id: \.offset) { offset, slide in
                slideCard(slide).tag(offset)
            }
        }
        #if canImport(UIKit)
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        #endif
    }

    private func slideCard(_ slide: ScanSlide) -> some View {
        VStack(spacing: 16) {
            Image(systemName: slide.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AuroraBrand.accentViola)
                .accessibilityHidden(true)
            Text(slide.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(slide.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if slide.isApproximate {
                Text("Dato approssimativo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func advance() {
        let count = content.slides.count
        guard count > 0 else { return }
        withAnimation(.easeInOut) {
            index = (index + 1) % count
        }
    }
}
#endif
