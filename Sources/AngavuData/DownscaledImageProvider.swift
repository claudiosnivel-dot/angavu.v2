import Foundation
import AngavuDomain

// FSE-C1 (Data) — Provider reale di immagine ridimensionata dietro il port
// `DownscaledImageProviding` (Domain).
//
// Sostituisce la decodifica full-res (`OnDeviceImageBytes.data` +
// `VNImageRequestHandler(data:)`) con `PHImageManager.requestImage(targetSize:)`:
// Photos decodifica DIRETTAMENTE alla taglia piccola richiesta, senza mai
// materializzare l'originale intero (leva 2, FAST-SCAN-ENGINE-PLAN §1.2).
//
// Onestà/privacy (§6): `isNetworkAccessAllowed = false` invariante — un originale
// solo in iCloud non è servibile offline → `nil` (mai un download, mai un byte fuori
// dal device, 00-INDEX §3). Un handle già risolto (FSE-B1) evita il refetch; un
// handle solo-id (`IdentifierAssetHandle`) ricade sul fetch per id, come oggi.
//
// Copertura dichiarata (L-COL-006): adapter Apple-only → compilato in CI, runtime sul
// device NON coperto (richiede una libreria PhotoKit reale). Il guadagno di velocità è
// device-only (§7). La logica di selezione taglia/condivisione è provata dagli oracoli
// di Domain/Features con provider fake.

#if canImport(Photos) && canImport(CoreGraphics)
import Photos
import CoreGraphics

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
private func cgImage(from image: PlatformImage) -> CGImage? {
    image.cgImage
}
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
private func cgImage(from image: PlatformImage) -> CGImage? {
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}
#endif

/// Immagine ridimensionata concreta: incapsula il `CGImage` piccolo. Gli adapter dei
/// rilevatori (nitidezza, feature print) la riconoscono per lavorarci senza ridecodificare.
final class PHDownscaledImage: DownscaledImage {
    let cgImage: CGImage
    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Estrae il `CGImage` da un'immagine ridimensionata opaca prodotta da questo Data
/// layer. `nil` se l'immagine non proviene da qui (mai un cast forzato).
extension DownscaledImage {
    var resolvedCGImage: CGImage? {
        (self as? PHDownscaledImage)?.cgImage
    }
}

#if canImport(UIKit) || canImport(AppKit)
/// Adapter reale: `PHImageManager.requestImage(targetSize:)` a taglia piccola, sincrono
/// verso il chiamante (che lo mette off-main), zero rete.
public struct PHImageDownscaledProvider: DownscaledImageProviding {
    public init() {}

    public func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        guard let phAsset = resolve(handle) else { return nil }

        let side = CGFloat(size.longestSide)
        let target = CGSize(width: side, height: side)

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false   // zero rete: non residente → nil, mai download
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        // `.fast`: Photos può restituire un'immagine leggermente più grande del target
        // ma decodificata piccola (mai full-res). L'esattezza al pixel non serve ai
        // rilevatori (feature print normalizza; la nitidezza ricampiona a griglia).
        options.resizeMode = .fast

        var platformImage: PlatformImage?
        _ = PHImageManager.default().requestImage(
            for: phAsset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            // Con `isNetworkAccessAllowed = false`, un originale solo in iCloud non è
            // servibile offline → `image` è nil (nessun download).
            platformImage = image
        }

        guard let platformImage, let downscaled = cgImage(from: platformImage) else { return nil }
        return PHDownscaledImage(downscaled)
    }

    /// PHAsset già risolto (FSE-B1, nessun refetch) o fetch per id come fallback.
    private func resolve(_ handle: AssetHandle) -> PHAsset? {
        if let resolved = handle.resolvedPHAsset { return resolved }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [handle.assetLocalIdentifier], options: nil)
        return fetch.firstObject
    }
}
#endif
#endif
