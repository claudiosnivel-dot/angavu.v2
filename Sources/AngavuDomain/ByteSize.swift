import Foundation

// T-014 — Dimensione in byte di un asset, con onestà esplicita sull'esattezza.
//
// Manifesto "numeri veri": una stima non va MAI spacciata per esatta. Il tipo
// distingue per costruzione `exact` da `estimated`; chi consuma il valore sa
// sempre quale delle due sta guardando.

/// Dimensione in byte, con marcatura di esattezza inseparabile dal valore.
public enum ByteSize: Equatable, Sendable {
    /// Valore esatto, ricavato da una risorsa che espone la dimensione reale.
    case exact(bytes: Int64)
    /// Valore stimato: la dimensione esatta non era disponibile. Mai presentabile
    /// come esatta.
    case estimated(bytes: Int64)

    /// Byte, qualunque sia il grado di certezza.
    public var bytes: Int64 {
        switch self {
        case .exact(let bytes), .estimated(let bytes):
            return bytes
        }
    }

    /// Vero solo per `exact`.
    public var isExact: Bool {
        if case .exact = self { return true }
        return false
    }
}

/// Input grezzo del Data layer: la dimensione esatta se disponibile, più una
/// stima di ripiego (es. derivata dai pixel) da usare quando manca l'esatta.
public struct RawResourceSize: Equatable, Sendable {
    /// Dimensione esatta in byte, se la risorsa la espone; altrimenti `nil`.
    public let exactBytes: Int64?
    /// Stima di ripiego, sempre presente (>= 0).
    public let fallbackEstimate: Int64

    public init(exactBytes: Int64?, fallbackEstimate: Int64) {
        self.exactBytes = exactBytes.map { max(0, $0) }
        self.fallbackEstimate = max(0, fallbackEstimate)
    }
}

/// Regola pura che sceglie fra esatto e stimato senza mai barare.
public enum ByteSizePolicy {
    /// Se la risorsa espone la dimensione esatta, la usa (`exact`); altrimenti
    /// degrada esplicitamente alla stima (`estimated`).
    public static func resolve(_ raw: RawResourceSize) -> ByteSize {
        if let exact = raw.exactBytes {
            return .exact(bytes: exact)
        }
        return .estimated(bytes: raw.fallbackEstimate)
    }
}
