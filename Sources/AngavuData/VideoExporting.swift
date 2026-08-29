import AngavuDomain

// T-081 (Data) — Export HEVC cancellabile con metadati preservati.
//
// Il protocollo e il coordinator sono puri (testabili con un fake); l'adapter
// reale su AVFoundation è guardato da `canImport(AVFoundation)`. Esito sempre
// esplicito (success | cancelled | failed): mai un blocco muto. Su failure il
// sorgente non è mai toccato (la sostituzione è un passo separato, T-082).

/// Capacità di ricodificare un video sorgente in HEVC. I test la sostituiscono
/// con un fake che riporta esiti noti.
public protocol VideoExporting {
    /// Ricodifica il video con l'identificatore dato, restituendo un esito esplicito.
    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome
}

/// Coordinatore puro: applica lo stop cooperativo prima di delegare all'exporter.
/// Se la cancellazione è già richiesta, non avvia nemmeno l'export.
public struct VideoExportCoordinator {
    private let exporter: VideoExporting

    public init(exporter: VideoExporting) {
        self.exporter = exporter
    }

    public func run(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        // Checkpoint di cancellazione PRIMA di avviare: niente export a vuoto.
        if cancellation.isCancelled { return .cancelled }
        return await exporter.export(
            sourceLocalIdentifier: sourceLocalIdentifier,
            preset: preset,
            cancellation: cancellation
        )
    }
}

#if canImport(AVFoundation) && canImport(Photos)
import AVFoundation
import Photos
import Foundation
import CoreLocation

/// Adapter reale su `AVAssetExportSession` con preset HEVC. Preserva i metadati
/// (data/luogo) dal sorgente. Usa l'API async moderna (iOS 18+/macOS 15+) per
/// evitare le API di export deprecate; su versioni precedenti degrada a `failed`
/// dichiarato (la compressione è opt-in e progressive).
public struct AVFoundationVideoExporter: VideoExporting {
    public init() {}

    public func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        if cancellation.isCancelled { return .cancelled }

        guard #available(iOS 18, macOS 15, *) else {
            return .failed(reason: "La compressione HEVC richiede iOS 18 o macOS 15.")
        }

        // Risolve il PHAsset sorgente.
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [sourceLocalIdentifier], options: nil)
        guard let asset = fetch.firstObject, asset.mediaType == .video else {
            return .failed(reason: "Video sorgente non trovato.")
        }

        // Ottiene l'AVAsset dal PHAsset.
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let sourceAsset = avAsset else {
            return .failed(reason: "Impossibile leggere il video sorgente (forse in iCloud).")
        }

        if cancellation.isCancelled { return .cancelled }

        // Configura l'export HEVC preservando i metadati del sorgente.
        guard let session = AVAssetExportSession(
            asset: sourceAsset,
            presetName: Self.presetName(for: preset)
        ) else {
            return .failed(reason: "Preset HEVC non disponibile per questo video.")
        }
        session.metadata = (try? await sourceAsset.load(.metadata)) ?? []

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        do {
            try await session.export(to: outputURL, as: .mov)
            let outputBytes = Self.fileSize(at: outputURL)
            let metadata = VideoMetadata(
                creationDate: asset.creationDate,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            )
            // FSE-J3: l'`outputURL` (file compresso su disco) viaggia con l'esito, così
            // la sostituzione può salvarlo in libreria PRIMA di eliminare l'originale.
            return .success(outputBytes: outputBytes, outputURL: outputURL, metadata: metadata)
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    /// Mappa il preset di dominio sul nome preset AVFoundation.
    private static func presetName(for preset: HEVCPreset) -> String {
        switch preset {
        case .highQuality: return AVAssetExportPresetHEVCHighestQuality
        case .balanced: return AVAssetExportPresetHEVC1920x1080
        }
    }

    /// Dimensione del file esportato in byte (0 se non leggibile).
    private static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
#endif
