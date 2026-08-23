import AngavuDomain

// Guscio UI — «Cosa NON facciamo»: presentazione PURA dei non-goals.
//
// Mappa `ManifestContent.nonGoals` (dominio puro, T-100) nelle decisioni di UI:
// intro, righe presentabili e — per ogni rinuncia — l'SF Symbol di categoria. È
// platform-puro (nessun import SwiftUI): l'ORACOLO testabile su Linux, così la resa
// SwiftUI resta il solo strato compilato-ma-non-testato (L-COL-006).
//
// Invariante di onestà portato in superficie (AC-100-2): ogni voce è una RINUNCIA
// dichiarata, mai un claim di capacità. La presentazione lo espone
// (`allAreRenunciations`) così la UI non può presentare un non-goal come feature.

/// Modello di presentazione della schermata dei non-goals.
public struct NonGoalsPresentation: Equatable, Sendable {
    /// Una riga presentabile: la rinuncia, il perché e la sua icona.
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: NonGoalID
        public let text: String
        public let rationale: String
        /// Nome dell'SF Symbol di categoria (dato di presentazione, nessun tipo UI).
        public let symbolName: String
    }

    /// Titolo della schermata.
    public let title: String
    /// Sottotitolo onesto: perché dichiariamo i limiti invece di simularli.
    public let subtitle: String
    /// Le righe, nell'ordine canonico del contenuto.
    public let rows: [Row]
    /// Vero sse OGNI voce è una rinuncia (nessun claim di capacità): deve restare
    /// vero per il contenuto canonico (AC-100-2). La UI si fida di questo, non
    /// coniuga da sé la marcatura.
    public let allAreRenunciations: Bool

    public init(content: ManifestContent = .angavu) {
        self.title = "Cosa NON facciamo"
        self.subtitle = "Alcune cose che i «cleaner» promettono sono impossibili su iOS. "
            + "Non le simuliamo: te lo diciamo."
        self.rows = content.nonGoals.map { goal in
            Row(
                id: goal.id,
                text: goal.text,
                rationale: goal.rationale,
                symbolName: Self.symbol(for: goal.id)
            )
        }
        self.allAreRenunciations = !content.anyNonGoalClaimsCapability
    }

    /// Numero di rinunce dichiarate.
    public var count: Int { rows.count }

    /// Mappa d'icona per categoria di rinuncia. SF Symbols di sistema (nessuna
    /// risorsa), coerenti col tono: uno "slash" dove neghiamo una capacità.
    static func symbol(for id: NonGoalID) -> String {
        switch id {
        case .systemCacheCleaning: return "internaldrive"
        case .otherAppFolders: return "folder.badge.questionmark"
        case .resourceBooster: return "bolt.slash"
        case .antivirus: return "shield.slash"
        case .noAds: return "hand.raised.slash"
        case .zeroBackend: return "icloud.slash"
        case .iapInV1: return "cart.badge.minus"
        case .advancedFeaturesDeferred: return "hourglass"
        }
    }
}
