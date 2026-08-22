// NonGoalsView — la schermata "cosa NON facciamo" (11-ui-shell.md, T-100).
//
// Dichiarare i limiti è un segnale di fiducia (e conformità App Store 2.3.x):
// niente scare tactics, niente claim impossibili. Ogni voce mostra la rinuncia e
// il perché. Contenuto dominio puro (`ManifestContent.nonGoals`); qui solo
// presentazione nativa HIG. Fuori dai target_tests di dominio (out_of_scope).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Schermata dei non-goals: cosa l'app dichiara di non fare, e perché.
public struct NonGoalsView: View {
    private let content: ManifestContent

    public init(content: ManifestContent = .angavu) {
        self.content = content
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                ForEach(content.nonGoals) { goal in
                    NonGoalRow(goal: goal)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cosa NON facciamo")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AuroraBrand.gradient)
            Text("Alcune cose che i \"cleaner\" promettono sono impossibili su iOS. Non le simuliamo: te lo diciamo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }
}

/// Riga di un singolo non-goal: rinuncia + motivazione.
private struct NonGoalRow: View {
    let goal: NonGoal

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goal.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AuroraBrand.accentFucsia)
        }
    }
}
#endif
