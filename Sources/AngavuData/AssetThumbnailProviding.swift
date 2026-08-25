import CoreGraphics

// A-1 — Port per le miniature reali degli asset (manifesto: «mai alla cieca»).
//
// Restituisce un `CGImage` (Core Graphics, cross-Apple → compila anche nella build
// macOS della CI) oppure `nil` quando l'originale non è servibile SENZA rete
// (residente solo in iCloud) o non esiste: la View mostra allora un placeholder
// onesto con glifo «in iCloud», non un'immagine finta. Definito nel Data (concerne
// PhotoKit); il Domain resta puro. Copertura dichiarata (L-COL-006): adapter
// Apple-only, compilato in CI, resa a runtime sul device NON coperta.
public protocol AssetThumbnailProviding: Sendable {
    /// Miniatura per l'asset, lato massimo `maxPixel` px. `nil` = non disponibile
    /// on-device senza rete (o asset assente). `isNetworkAccessAllowed=false`: mai
    /// download iCloud dietro le quinte.
    func thumbnail(forLocalIdentifier id: String, maxPixel: Int) async -> CGImage?
}

/// Null-object: nessuna miniatura. Default dell'`AppEnvironment` finché il grafo
/// reale non inietta l'adapter di sistema; la View ricade sul placeholder.
public struct NoThumbnailProvider: AssetThumbnailProviding {
    public init() {}
    public func thumbnail(forLocalIdentifier id: String, maxPixel: Int) async -> CGImage? { nil }
}

#if canImport(Photos) && canImport(UIKit)
import Photos
import UIKit

/// Adapter reale via `PHCachingImageManager`, on-device (`isNetworkAccessAllowed=false`),
/// low-RAM (targetSize ridotto, `resizeMode=.fast`). Un asset i cui originali sono
/// solo in iCloud → `nil` (la View mostra il glifo «in iCloud»), mai un download
/// silenzioso. `deliveryMode=.highQualityFormat` → una sola consegna per richiesta.
public final class PHCachingThumbnailProvider: AssetThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()

    public init() {}

    public func thumbnail(forLocalIdentifier id: String, maxPixel: Int) async -> CGImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false   // zero rete: solo ciò che è on-device
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        let size = CGSize(width: maxPixel, height: maxPixel)
        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            let sink = ContinuationSink(continuation)
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Ignora eventuali consegne degradate intermedie: risolvi una volta sola.
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                sink.resume(with: image?.cgImage)
            }
        }
    }
}

/// Garantisce una sola ripresa della continuation anche se il completion di PhotoKit
/// fosse invocato più volte (crash altrimenti).
private final class ContinuationSink: @unchecked Sendable {
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<CGImage?, Never>) {
        self.continuation = continuation
    }

    func resume(with image: CGImage?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: image)
    }
}
#endif
