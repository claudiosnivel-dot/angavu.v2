// NonGoalsView — la schermata "cosa NON facciamo" (11-ui-shell.md, T-100).
//
// Dichiarare i limiti è un segnale di fiducia (e conformità App Store 2.3.x):
// niente scare tactics, niente claim impossibili. Ogni voce mostra la rinuncia e
// il perché, con l'SF Symbol di categoria. Le decisioni di presentazione vivono in
// `NonGoalsPresentation` (puro, testato); qui c'è solo il rendering SwiftUI, guardato
// `#if canImport(SwiftUI)` — il solo strato compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Schermata dei non-goals: cosa l'app dichiara di non fare, e perché.
public struct NonGoalsView: View {
    private let presentation: NonGoalsPresentation

    public init(content: ManifestContent = .angavu) {
        self.presentation = NonGoalsPresentation(content: content)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                ForEach(presentation.rows) { row in
                    NonGoalRow(row: row)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle(presentation.title)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
                .accessibilityAddTraits(.isHeader)
            Text(presentation.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }
}

/// Riga di un singolo non-goal: icona di categoria + rinuncia + motivazione.
private struct NonGoalRow: View {
    let row: NonGoalsPresentation.Row

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: row.symbolName)
                .foregroundStyle(AuroraBrand.accentFucsia)
                .accessibilityHidden(true)
        }
        // VoiceOver: rinuncia + motivazione come un solo elemento leggibile.
        .accessibilityElement(children: .combine)
    }
}
#endif
