// AuroraType — descrizione PURA (platform-agnostic) della tipografia di brand.
// R-01: la cifra-hero (il numero più importante di ogni schermata) usava una
// dimensione FISSA `.font(.system(size: 44 …))` che NON scala col Dynamic Type e
// si tronca alle accessibility sizes, con `monospacedDigit` incoerente. Qui la
// scelta di stile è espressa come DATI (nessun import SwiftUI), così è l'oracolo
// testabile su Linux (L-COL-006); la resa reale in modificatori vive in
// AuroraTheme.swift sotto `#if canImport(SwiftUI)` come unico punto di traduzione.

/// La tipografia d'identità del brand Angavu, come descrizione pura.
public enum AuroraType {
    /// Cap superiore del Dynamic Type per una cifra-hero: scala fino a una taglia
    /// accessibile ragionevole senza troncare il numero alle AX sizes estreme.
    public enum DynamicTypeCap: String, Equatable, Sendable {
        case accessibility3
    }

    /// Stile della cifra-hero: un text style SEMANTICO (scala con Dynamic Type),
    /// non una dimensione fissa; cifre monospaziate per non "ballare" mentre
    /// cambiano a runtime. Descrizione pura, tradotta in `Font`/modificatori dalla
    /// View.
    public struct HeroNumberStyle: Equatable, Sendable {
        /// Text style semantico Dynamic Type (mappato a `Font.TextStyle` nella View).
        public enum TextStyle: String, Equatable, Sendable {
            case largeTitle
            case title
        }

        /// Il text style di base (scala col Dynamic Type dell'utente).
        public let textStyle: TextStyle
        /// Design arrotondato (coerente col carattere del brand).
        public let rounded: Bool
        /// Peso grassetto.
        public let bold: Bool
        /// Cifre a larghezza fissa: il numero non si allarga/stringe mentre cambia.
        public let monospacedDigit: Bool
        /// Cap superiore del Dynamic Type (niente troncamento alle AX sizes).
        public let dynamicTypeCap: DynamicTypeCap

        public init(
            textStyle: TextStyle,
            rounded: Bool,
            bold: Bool,
            monospacedDigit: Bool,
            dynamicTypeCap: DynamicTypeCap
        ) {
            self.textStyle = textStyle
            self.rounded = rounded
            self.bold = bold
            self.monospacedDigit = monospacedDigit
            self.dynamicTypeCap = dynamicTypeCap
        }
    }

    /// L'UNICO stile cifra-hero, riusato da tutte le schermate (Dashboard, Review
    /// categorie, Report onesto, Compressione). Un solo posto da cui deriva la resa.
    public static let heroNumber = HeroNumberStyle(
        textStyle: .largeTitle,
        rounded: true,
        bold: true,
        monospacedDigit: true,
        dynamicTypeCap: .accessibility3
    )
}
