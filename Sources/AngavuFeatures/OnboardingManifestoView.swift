// OnboardingManifestoView — la voce dell'app all'avvio (11-ui-shell.md, T-100).
//
// Onboarding-manifesto nativo HIG: wordmark col gradiente d'accento (uso
// parsimonioso), headline, le promesse positive con SF Symbols, e la porta verso
// «Cosa NON facciamo» — un `NavigationLink` reale (l'onboarding vive dentro un
// `NavigationStack`), non una scorciatoia che salta l'onboarding.
//
// Le decisioni di presentazione vivono in `OnboardingManifestoPresentation` (puro,
// testato); qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` —
// il solo strato compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Schermata di onboarding-manifesto.
public struct OnboardingManifestoView: View {
    private let presentation: OnboardingManifestoPresentation
    private let onContinue: () -> Void

    public init(
        content: ManifestContent = .angavu,
        onContinue: @escaping () -> Void = {}
    ) {
        self.presentation = OnboardingManifestoPresentation(content: content)
        self.onContinue = onContinue
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
            Text(presentation.wordmark)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
            Text(presentation.headline)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private var promisesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(presentation.promises) { promise in
                Label {
                    Text(promise.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: promise.symbolName)
                        .foregroundStyle(AuroraBrand.accentViola)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var nonGoalsLink: some View {
        NavigationLink {
            NonGoalsView()
        } label: {
            Label(presentation.nonGoalsLinkTitle, systemImage: "xmark.seal")
                .font(.headline)
        }
        .foregroundStyle(AuroraBrand.accentFucsia)
    }

    private var continueBar: some View {
        Button(action: onContinue) {
            Text(presentation.continueTitle)
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
