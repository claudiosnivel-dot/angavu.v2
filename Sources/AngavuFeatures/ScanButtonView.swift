// E-2 (guscio UI) — Il tasto gigante centrale del flusso "Shazam".
//
// Batte come un cuore durante la richiesta permessi (fase INDETERMINATA) e si
// riempie come un livello d'acqua durante l'analisi (frazione REALE di
// `AnalysisProgress`, mai fabbricata). TUTTE le animazioni sono gated su Reduce
// Motion, con equivalente statico a parità informativa (coerente con R-06): senza
// motion il tasto non pulsa e il riempimento salta al livello reale senza tween —
// lo stato resta leggibile dall'etichetta e dal carosello. SwiftUI puro, offline,
// zero dipendenze; compilato-ma-non-reso (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

struct ScanButtonView: View {
    let flow: ScanFlowPresentation
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beating = false

    private let diameter: CGFloat = 240

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(.thinMaterial)
                waterFill
                Circle().strokeBorder(AuroraBrand.gradient, lineWidth: 8)
                label.padding(28)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulseScale)
            .animation(heartbeat, value: pulseScale)
        }
        .buttonStyle(.plain)
        .disabled(!flow.isButtonEnabled)
        .onAppear { beating = flow.isIndeterminate }
        .onChange(of: flow.isIndeterminate) { _, indeterminate in
            beating = indeterminate
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(flow.isButtonEnabled ? .isButton : [])
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(flow.statusLabel ?? "")
    }

    // MARK: Riempimento "acqua" — ancorato in basso, ritagliato nel cerchio.

    private var waterFill: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                AuroraBrand.gradient
                    .frame(height: geo.size.height * CGFloat(flow.fill ?? 0))
                    .opacity(0.85)
            }
        }
        .clipShape(Circle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: flow.fill)
    }

    // MARK: Battito — solo in fase indeterminata e solo con motion consentito.

    private var pulseScale: CGFloat {
        (beating && !reduceMotion) ? 1.06 : 1.0
    }

    private var heartbeat: Animation? {
        guard !reduceMotion, flow.isIndeterminate else { return nil }
        return .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
    }

    // MARK: Etichetta al centro del tasto (cambia con la fase).

    @ViewBuilder private var label: some View {
        switch flow.phase {
        case .ready:
            VStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 52, weight: .semibold))
                Text(flow.buttonTitle)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(AuroraBrand.accentViola)
        case .preparing, .scanning:
            VStack(spacing: 8) {
                if let status = flow.statusLabel {
                    Text(status)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                }
                Text(flow.isIndeterminate ? "un momento…" : (flow.stageTitle ?? "Analisi in corso"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .finished:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        switch flow.phase {
        case .ready: return flow.buttonTitle
        case .preparing, .scanning: return "Analisi della libreria in corso"
        case .finished: return ""
        }
    }
}
#endif
