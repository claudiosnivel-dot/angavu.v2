import Foundation

// T-080 — Stima del risparmio (marcata stima) e gate opt-in per la compressione.
// Più i tipi condivisi con l'export (T-081) e la sostituzione (T-082).
//
// Manifesto onestà: il risparmio è SEMPRE una stima (`ByteSize.estimated`), mai un
// numero garantito. E nessuna compressione parte senza consenso esplicito
// (opt-in), modellato come stato puro nel Domain. Nessun import di AVFoundation.

/// Preset di ricodifica HEVC. `bitrateFactor` = frazione del bitrate sorgente
/// attesa dopo la ricodifica (HEVC rende qualità simile a ~metà bitrate di H.264).
public enum HEVCPreset: String, Equatable, Sendable, CaseIterable {
    case highQuality
    case balanced

    /// Fattore di bitrate atteso (0…1). Deterministico e conservativo.
    public var bitrateFactor: Double {
        switch self {
        case .highQuality: return 0.60
        case .balanced: return 0.45
        }
    }
}

/// Caratteristiche note di un video candidato alla compressione.
public struct VideoSpec: Equatable, Sendable {
    /// Byte occupati dal video sorgente.
    public let originalBytes: Int64
    /// Durata in secondi (>= 0).
    public let durationSeconds: Double
    /// Bitrate sorgente in bit al secondo (>= 0).
    public let sourceBitrateBitsPerSec: Int64

    public init(originalBytes: Int64, durationSeconds: Double, sourceBitrateBitsPerSec: Int64) {
        self.originalBytes = max(0, originalBytes)
        self.durationSeconds = max(0, durationSeconds)
        self.sourceBitrateBitsPerSec = max(0, sourceBitrateBitsPerSec)
    }
}

/// Stima pura del risparmio da una ricodifica HEVC.
public enum CompressionEstimator {
    /// Stima i byte risparmiati. Il risultato è **sempre** `ByteSize.estimated`:
    /// la compressione reale può divergere, non si promette mai un valore esatto.
    /// Se la ricodifica non porta vantaggio (stima >= sorgente), il risparmio è 0.
    public static func estimatedSaving(for spec: VideoSpec, preset: HEVCPreset) -> ByteSize {
        let targetBitrate = Double(spec.sourceBitrateBitsPerSec) * preset.bitrateFactor
        let estimatedCompressedBytes = Int64((targetBitrate * spec.durationSeconds) / 8.0)
        let saved = max(0, spec.originalBytes - estimatedCompressedBytes)
        return .estimated(bytes: saved)
    }
}

/// Gate opt-in: nessuna compressione parte senza consenso esplicito per gli asset.
public struct CompressionOptIn: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case consented(assets: [String])
    }

    public private(set) var state: State

    public init() {
        self.state = .idle
    }

    /// Registra il consenso esplicito per un batch. Un batch vuoto è rifiutato.
    @discardableResult
    public mutating func grantConsent(for ids: [String]) -> Bool {
        guard !ids.isEmpty else { return false }
        state = .consented(assets: ids)
        return true
    }

    /// Revoca il consenso (torna a idle).
    public mutating func revoke() {
        state = .idle
    }

    /// L'avvio è consentito SOLO se esiste un consenso che copre tutti gli id
    /// richiesti. Senza consenso (o con id non coperti) l'avvio è rifiutato.
    public func canStart(_ ids: [String]) -> Bool {
        guard case .consented(let consented) = state, !ids.isEmpty else { return false }
        let granted = Set(consented)
        return ids.allSatisfy { granted.contains($0) }
    }
}

// MARK: - Tipi condivisi con export (T-081) e sostituzione (T-082)

/// Metadati del video da preservare attraverso la ricodifica.
public struct VideoMetadata: Equatable, Sendable {
    public let creationDate: Date?
    public let latitude: Double?
    public let longitude: Double?

    public init(creationDate: Date?, latitude: Double?, longitude: Double?) {
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Esito esplicito di un export: mai un blocco muto, sempre uno di questi tre.
public enum VideoExportOutcome: Equatable, Sendable {
    /// Ricodifica riuscita: byte dell'output e metadati preservati.
    case success(outputBytes: Int64, metadata: VideoMetadata)
    /// Cancellata (stop cooperativo): nessun output valido, sorgente intatto.
    case cancelled
    /// Fallita: motivo ispezionabile; il sorgente resta intatto.
    case failed(reason: String)
}
