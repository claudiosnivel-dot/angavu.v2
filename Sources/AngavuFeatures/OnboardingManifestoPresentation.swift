import AngavuDomain

// Guscio UI — Onboarding-manifesto: presentazione PURA della voce d'apertura.
//
// Mappa `ManifestContent` (dominio puro, T-100) nelle decisioni di UI: wordmark,
// headline, le promesse positive con l'SF Symbol relativo, e le etichette dei
// controlli. Platform-puro (nessun import SwiftUI): l'ORACOLO testabile su Linux,
// così la resa SwiftUI resta il solo strato compilato-ma-non-testato (L-COL-006).
//
// Invariante di onestà portato in superficie (AC-100-2): ogni promessa è mantenibile
// ON-DEVICE. La presentazione lo espone (`allPromisesOnDevice`) così la UI non
// annuncia nulla che il sandbox iOS renda impossibile.

/// Modello di presentazione della schermata di onboarding-manifesto.
public struct OnboardingManifestoPresentation: Equatable, Sendable {
    /// Una promessa presentabile: il testo e la sua icona.
    public struct PromiseRow: Equatable, Sendable, Identifiable {
        public let id: ManifestPromiseID
        public let text: String
        /// Nome dell'SF Symbol (dato di presentazione, nessun tipo UI).
        public let symbolName: String
    }

    /// Wordmark del brand (usato col gradiente d'accento, con parsimonia).
    public let wordmark: String
    /// Promessa d'apertura (headline del manifesto).
    public let headline: String
    /// Le promesse positive, nell'ordine canonico del contenuto.
    public let promises: [PromiseRow]
    /// Etichetta del link verso «Cosa NON facciamo».
    public let nonGoalsLinkTitle: String
    /// Etichetta del pulsante primario che chiude l'onboarding.
    public let continueTitle: String
    /// Vero sse OGNI promessa è mantenibile on-device: deve restare vero per il
    /// contenuto canonico (AC-100-2). La UI si fida di questo.
    public let allPromisesOnDevice: Bool

    public init(content: ManifestContent = .angavu) {
        self.wordmark = "Angavu"
        self.headline = content.headline
        self.promises = content.promises.map { promise in
            PromiseRow(id: promise.id, text: promise.text, symbolName: Self.symbol(for: promise.id))
        }
        self.nonGoalsLinkTitle = "Cosa NON facciamo"
        self.continueTitle = "Inizia"
        self.allPromisesOnDevice = content.allPromisesAchievableOnDevice
    }

    /// Mappa d'icona per promessa. SF Symbols di sistema (nessuna risorsa).
    static func symbol(for id: ManifestPromiseID) -> String {
        switch id {
        case .offline: return "wifi.slash"
        case .noAds: return "hand.raised.slash"
        case .realNumbers: return "number"
        case .safetyNet: return "checkmark.shield"
        case .onePayment: return "creditcard"
        }
    }
}
