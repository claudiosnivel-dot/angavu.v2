// E-1/E-2 (resa) — La schermata del flusso "Shazam": metà superiore (wordmark a
// riposo, carosello durante il lavoro) + tasto gigante centrale + didascalia. Un
// solo tap dall'apertura al risultato; nessuno stato "idle" separato con bottone da
// modulo. Le decisioni sono nel layer PURO `ScanFlowPresentation`; qui c'è solo la
// resa SwiftUI, compilata-ma-non-resa (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

struct ScanFlowScreen: View {
    let flow: ScanFlowPresentation
    let carousel: ScanCarouselContent
    let onTap: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            topArea
            ScanButtonView(flow: flow, onTap: onTap)
            if let caption = flow.buttonCaption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            if flow.canCancel {
                cancelButton
            }
            if flow.phase == .ready {
                nonGoalsLink
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text("Annulla")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }

    // Metà superiore: a riposo il wordmark, durante il lavoro il carosello.
    @ViewBuilder private var topArea: some View {
        if flow.showsCarousel {
            ScanCarouselView(content: carousel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Text("Angavu")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AuroraBrand.gradient)
                    .accessibilityAddTraits(.isHeader)
                Text("Numeri veri, sul tuo dispositivo.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var nonGoalsLink: some View {
        NavigationLink {
            NonGoalsView()
        } label: {
            Label("Cosa NON facciamo", systemImage: "xmark.seal")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(AuroraBrand.accentFucsia)
        .padding(.top, 4)
    }
}
#endif
