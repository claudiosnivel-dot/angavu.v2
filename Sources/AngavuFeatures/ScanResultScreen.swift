// E-3 (resa) — Schermata di risultato: festa (successo pieno) o ramo onesto
// (parziale/errore). La DECISIONE è nel layer PURO `ScanSuccessPresentation`; qui
// c'è solo la resa. I coriandoli sono riservati alla festa e comunque gated su
// Reduce Motion, con equivalente statico (uno scoppio di stelline fermo) a parità
// informativa (coerente con R-06 e col game-feel: rarità = festa più grande).
// View-level, compilata-ma-non-resa (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

struct ScanResultScreen: View {
    let result: ScanSuccessPresentation
    let onPrimary: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            if result.showsConfetti {
                ConfettiView().ignoresSafeArea()
            }
            content
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Spacer()
            icon
            Text(result.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(result.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Spacer()
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: some View {
        Image(systemName: result.style == .celebration ? "sparkles" : "exclamationmark.circle")
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(iconStyle)
            .accessibilityHidden(true)
    }

    private var iconStyle: AnyShapeStyle {
        result.style == .celebration
            ? AnyShapeStyle(AuroraBrand.gradient)
            : AnyShapeStyle(Color.secondary)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onPrimary) {
                Text(result.primaryActionTitle)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AuroraBrand.gradient, in: .capsule)
                    .foregroundStyle(AuroraBrand.onGradient)
            }
            if result.offersOpenSettings {
                Button(action: onOpenSettings) {
                    Label("Apri Impostazioni", systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
#endif
