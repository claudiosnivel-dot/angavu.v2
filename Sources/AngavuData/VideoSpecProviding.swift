import AngavuDomain

// Guscio UI (wiring della compressione) — Lettura on-device della `VideoSpec`
// (durata + bitrate) di un video, dietro un port testabile.
//
// ONESTÀ / NUMERI VERI: la stima del risparmio (T-080, `CompressionEstimator`)
// ha bisogno di durata e bitrate del sorgente. Questi NON sono nell'indice
// (library_index conserva pixel/data/subtype, non la durata/bitrate) e si leggono
// solo on-device dall'`AVAsset`. Qui il port astrae quella lettura: i test la
// sostituiscono con un fake e non fabbricano mai i numeri; l'adapter reale su
// AVFoundation è guardato `#if canImport(AVFoundation)` (compilato in CI, runtime
// device-only, dichiarato non coperto). I byte del sorgente arrivano già VERI
// dall'indice (`AssetByteSizeResolving`), non ristimati qui.

/// Capacità di leggere durata e bitrate di un video sorgente. `nil` quando la spec
/// non è disponibile off-device (asset non trovato, non video, o dati non leggibili
/// senza rete): mai un numero inventato al suo posto.
public protocol VideoSpecProviding {
    /// Legge la spec del video con l'identificatore dato. `originalBytes` è la
    /// dimensione VERA già nota dall'indice, riportata invariata nella spec; qui si
    /// aggiungono solo durata e bitrate letti on-device.
    func videoSpec(forLocalIdentifier id: String, originalBytes: Int64) async -> VideoSpec?
}

#if canImport(AVFoundation) && canImport(Photos)
import AVFoundation
import Photos
import CoreMedia

/// Adapter reale: risolve il `PHAsset`, ne carica l'`AVAsset` senza rete
/// (`isNetworkAccessAllowed = false`), e legge durata + bitrate stimato dalla
/// traccia video con le API async moderne. Se qualcosa manca (non è un video, non
/// c'è traccia, dati non leggibili), restituisce `nil` — mai una stima finta.
public struct AVFoundationVideoSpecProvider: VideoSpecProviding {
    public init() {}

    public func videoSpec(forLocalIdentifier id: String, originalBytes: Int64) async -> VideoSpec? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject, asset.mediaType == .video else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let sourceAsset = avAsset else { return nil }

        do {
            let duration = try await sourceAsset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds >= 0 else { return nil }

            let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return nil }
            let dataRate = try await track.load(.estimatedDataRate) // bit/sec (Float)
            guard dataRate.isFinite, dataRate >= 0 else { return nil }

            return VideoSpec(
                originalBytes: originalBytes,
                durationSeconds: seconds,
                sourceBitrateBitsPerSec: Int64(dataRate)
            )
        } catch {
            return nil
        }
    }
}
#endif
