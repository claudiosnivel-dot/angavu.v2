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

#if canImport(Photos)
import Photos

/// Adapter reale (B-1). **Non dipende più dall'`AVAsset`**: caricarlo con
/// `requestAVAsset` FALLISCE sugli originali in iCloud (iCloud "Ottimizza spazio"
/// attivo) — il difetto «Non riesco a leggere durata/bitrate» del device-test. La
/// durata si legge da `PHAsset.duration`, un **metadato locale** presente anche
/// quando l'originale è nel cloud (nessun download). Il bitrate è quello **medio**
/// dai byte VERI (già noti dall'indice): `byte * 8 / durata`. Restituisce `nil` solo
/// se non è un video o la durata è assente/non valida — mai un numero inventato.
/// Copertura (L-COL-006): adapter Apple-only, compilato in CI, runtime device-only.
public struct AVFoundationVideoSpecProvider: VideoSpecProviding {
    public init() {}

    public func videoSpec(forLocalIdentifier id: String, originalBytes: Int64) async -> VideoSpec? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject, asset.mediaType == .video else { return nil }

        // Durata da PHAsset (locale, nessuna rete): funziona anche in iCloud.
        let seconds = asset.duration
        guard seconds.isFinite, seconds > 0 else { return nil }

        // Bitrate MEDIO dai byte reali dell'indice e la durata locale.
        let bitrate = Int64((Double(originalBytes) * 8.0 / seconds).rounded())

        return VideoSpec(
            originalBytes: originalBytes,
            durationSeconds: seconds,
            sourceBitrateBitsPerSec: max(0, bitrate)
        )
    }
}
#endif
