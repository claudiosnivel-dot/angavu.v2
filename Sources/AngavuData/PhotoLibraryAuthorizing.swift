import AngavuDomain

// T-010 (Data) — Autorizzazione alla libreria foto.
//
// Il protocollo raffina il port puro `PhotoAccessProviding` del Domain, aggiungendo
// la richiesta interattiva. L'implementazione concreta tocca PhotoKit ed è quindi
// compilata solo dove `Photos` è disponibile (device/simulatore Apple); su Linux
// il file compila senza la parte guardata, preservando l'altitudine e la build.

/// Capacità di leggere e richiedere l'autorizzazione alla libreria, normalizzata
/// a `PhotoAccess`. I test la sostituiscono con un fake puro.
public protocol PhotoLibraryAuthorizing: PhotoAccessProviding {
    /// Richiede l'accesso all'utente (idempotente se già concesso) e restituisce
    /// la modalità risultante.
    func requestAccess() async -> PhotoAccess
}

#if canImport(Photos)
import Photos

/// Adapter reale su PhotoKit. Mappa `PHAuthorizationStatus` in `PhotoAccess`.
public struct SystemPhotoLibraryAuthorizer: PhotoLibraryAuthorizing {
    public init() {}

    public func currentAccess() -> PhotoAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> PhotoAccess {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.map(status)
    }

    /// Traduzione totale: ogni caso di PhotoKit ha una modalità di dominio.
    /// `restricted` è trattato come `denied` (l'app non può accedere).
    static func map(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
#endif
