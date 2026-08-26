import AngavuDomain

// D-2 (guscio UI, platform-puro) — Presentazione dell'indicatore d'avanzamento.
//
// Mappa lo stato d'avanzamento di un calcolo in una decisione osservabile per la
// View: barra DETERMINATA (frazione reale + "X di N") quando il motore riporta un
// `AnalysisProgress`, altrimenti indicatore INDETERMINATO etichettato. Mai una
// frazione fabbricata: se il calcolo non sa dire X/N (es. un fetch in blocco che
// non espone conteggi per-item), l'onestà impone l'indeterminato (manifesto:
// numeri veri, mai un progresso "teatrale"). È l'ORACOLO testabile; la resa
// SwiftUI (`ProgressView(value:)` vs spinner) è View-level non coperta (L-COL-006).
//
// Nessun import SwiftUI: come `HomeScanPresentation`, resta lo strato puro così la
// View è il solo "compilato-ma-non-testato".
public struct AnalysisProgressPresentation: Equatable, Sendable {
    /// Vero → barra determinata (usa `fraction`); falso → indeterminata (spinner).
    public let isDeterminate: Bool
    /// Frazione 0…1 per `ProgressView(value:)`, presente SOLO se determinata.
    public let fraction: Double?
    /// Etichetta sempre presente (testo + accessibilità): "X di N" quando
    /// determinata, altrimenti la label indeterminata fornita dal chiamante.
    public let label: String

    /// Deriva la presentazione da un avanzamento opzionale. `progress == nil`
    /// (calcolo senza conteggi affidabili) ⇒ indeterminato, senza inventare una
    /// frazione. Deterministica e totale.
    public init(progress: AnalysisProgress?, indeterminateLabel: String) {
        if let progress {
            self.isDeterminate = true
            self.fraction = progress.fraction
            self.label = "\(progress.processed) di \(progress.total)"
        } else {
            self.isDeterminate = false
            self.fraction = nil
            self.label = indeterminateLabel
        }
    }
}
