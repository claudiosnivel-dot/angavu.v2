import Foundation

// Selezione del tema dell'app: segui il sistema, oppure forza chiaro/scuro.
// Puro e testabile: il mapping a SwiftUI (`ColorScheme`) vive in AngavuFeatures
// (guardato). Persistenza via stringa (UserDefaults / @AppStorage).

public enum ThemeChoice: String, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark

    /// Default quando non c'è (ancora) una preferenza salvata.
    public static let fallback: ThemeChoice = .system

    /// Ricostruisce la scelta da un valore salvato; un valore assente o
    /// sconosciuto ricade sul default (`system`), mai un crash.
    public init(storageValue: String?) {
        self = ThemeChoice(rawValue: storageValue ?? "") ?? .fallback
    }

    /// Valore da persistere.
    public var storageValue: String { rawValue }
}
