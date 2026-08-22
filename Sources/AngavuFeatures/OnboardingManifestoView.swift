// OnboardingManifestoView — la voce dell'app all'avvio (11-ui-shell.md, T-100).
//
// Onboarding-manifesto nativo HIG: wordmark col gradiente d'accento (uso
// parsimonioso), headline, le promesse positive con SF Symbols, e la porta verso
// "cosa NON facciamo". Tipografia di sistema (SF Pro) + Dynamic Type: nessuna
// dimensione cablata. Il contenuto è dominio puro (`ManifestContent`), qui solo
// presentazione. Fuori dai target_tests di dominio (out_of_scope).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Icona (SF Symbol) per ogni promessa del manifesto: mappa di presentazione.
private func symbol(for promise: ManifestPromiseID) -> String {
    switch promise {
    case .offline: return "wifi.slash"
    case .noAds: return "hand.raised.slash"
    case .realNumbers: return "number"
    case .safetyNet: return "checkmark.shield"
    case .onePayment: return "creditcard"
    }
}

/// Schermata di onboarding-manifesto.
public struct OnboardingManifestoView: View {
    private let content: ManifestContent
    private let onContinue: () -> Void
    private let onShowNonGoals: () -> Void

    public init(
        content: ManifestContent = .angavu,
        onContinue: @escaping () -> Void = {},
        onShowNonGoals: @escaping () -> Void = {}
    ) {
        self.content = content
        self.onContinue = onContinue
        self.onShowNonGoals = onShowNonGoals
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                promisesList
                nonGoalsLink
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backdrop)
        .safeAreaInset(edge: .bottom) { continueBar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Angavu")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
            Text(content.headline)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private var promisesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(content.promises) { promise in
                Label {
                    Text(promise.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol(for: promise.id))
                        .foregroundStyle(AuroraBrand.accentViola)
                }
            }
        }
    }

    private var nonGoalsLink: some View {
        Button(action: onShowNonGoals) {
            Label("Cosa NON facciamo", systemImage: "xmark.seal")
                .font(.headline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AuroraBrand.accentFucsia)
    }

    private var continueBar: some View {
        Button(action: onContinue) {
            Text("Inizia")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AuroraBrand.gradient, in: .capsule)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var backdrop: some View {
        AuroraBrand.glow
            .ignoresSafeArea()
    }
}
#endif
