import Foundation

// T-010 — Stato di autorizzazione alla libreria foto e sua policy, nel Domain PURO.
//
// L'invariante di prodotto (manifesto onestà): un accesso `limited` NON va mai
// spacciato per totale. La policy lo marca esplicitamente come conteggio parziale,
// così le feature a valle non possono dichiarare un numero pieno per errore.
// Nessun import di Photos: il mapping da PHAuthorizationStatus vive nell'adapter
// del Data layer (altitudine, 00-INDEX §1bis).

/// Modalità d'accesso alla libreria, indipendente dalla piattaforma.
public enum PhotoAccess: String, Equatable, Sendable, CaseIterable {
    case notDetermined
    case denied
    case limited
    case full
}

/// Port del Domain per conoscere la modalità d'accesso corrente. L'adapter PhotoKit
/// del Data layer vi si conforma; i test lo sostituiscono con un fake puro.
public protocol PhotoAccessProviding {
    /// Modalità d'accesso corrente, già normalizzata a `PhotoAccess`.
    func currentAccess() -> PhotoAccess
}

/// Decisione derivata dalla modalità d'accesso: cosa la app può fare, e con quale
/// onestà sui numeri.
public struct PhotoAccessDecision: Equatable, Sendable {
    /// Modalità d'accesso valutata.
    public let access: PhotoAccess
    /// Vero quando l'accesso è `limited`: il conteggio è parziale e non va
    /// presentato come totale.
    public let isPartialCount: Bool
    /// Vero quando ha senso tentare l'enumerazione (accesso `full` o `limited`).
    public let shouldEnumerate: Bool

    public init(access: PhotoAccess, isPartialCount: Bool, shouldEnumerate: Bool) {
        self.access = access
        self.isPartialCount = isPartialCount
        self.shouldEnumerate = shouldEnumerate
    }
}

/// Regola pura che traduce una modalità d'accesso nelle sue conseguenze.
public enum PhotoAccessPolicy {
    /// Decide le conseguenze di una modalità d'accesso. Deterministica e totale.
    public static func decide(for access: PhotoAccess) -> PhotoAccessDecision {
        switch access {
        case .full:
            return PhotoAccessDecision(access: .full, isPartialCount: false, shouldEnumerate: true)
        case .limited:
            // Accesso parziale: enumerabile, ma il conteggio NON è totale.
            return PhotoAccessDecision(access: .limited, isPartialCount: true, shouldEnumerate: true)
        case .denied:
            // Negato: nessuna enumerazione va tentata.
            return PhotoAccessDecision(access: .denied, isPartialCount: false, shouldEnumerate: false)
        case .notDetermined:
            // Non ancora deciso: si attende la richiesta, nessuna enumerazione.
            return PhotoAccessDecision(access: .notDetermined, isPartialCount: false, shouldEnumerate: false)
        }
    }

    /// Comodità: decide direttamente dal provider (usata dalle feature).
    public static func decide(from provider: PhotoAccessProviding) -> PhotoAccessDecision {
        decide(for: provider.currentAccess())
    }
}
