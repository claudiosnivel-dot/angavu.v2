import Foundation
import AngavuDomain

// T-041 (Data) — dHash percettivo a 64 bit, fallback economico del clustering.
//
// Il fallback vive nel Domain come aritmetica di Hamming pura (`SimilarClustering`);
// qui si produce il valore a 64 bit da cui quella distanza si calcola. È un hash
// PERCETTIVO (immagini simili → dHash vicini), non crittografico: serve solo quando
// il feature print Vision manca per un asset.
//
// Algoritmo dHash classico: riduci a 9×8 in scala di grigi, poi per ogni riga
// confronta i pixel adiacenti (8 confronti × 8 righe = 64 bit). Robusto a scala e
// piccole variazioni. Solo on-device (`isNetworkAccessAllowed = false`, zero rete).
// Cross-Apple: ImageIO + CoreGraphics (niente UIKit), così compila anche sull'host
// macOS della CI, non solo su iOS.

#if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
import Photos
import ImageIO
import CoreGraphics

/// Produttore reale del dHash percettivo di un asset. `nil` se i pixel non sono
/// leggibili on-device o l'immagine non è decodificabile: un asset senza dHash e
/// senza feature print non verrà mai dichiarato simile (nessun falso "via libera").
public struct PerceptualDHasher {
    /// Larghezza campionata (9): 8 confronti orizzontali per riga.
    private static let sampleWidth = 9
    /// Altezza campionata (8): 8 righe → 64 bit totali.
    private static let sampleHeight = 8

    public init() {}

    /// dHash a 64 bit dell'asset, o `nil` se non calcolabile on-device.
    public func dHash(for asset: LibraryAsset) -> UInt64? {
        guard
            let data = imageData(for: asset),
            let gray = grayscaleSamples(from: data)
        else {
            return nil
        }
        return Self.dHash(fromGray: gray)
    }

    /// Byte dell'immagine, letti SOLO on-device (zero rete).
    private func imageData(for asset: LibraryAsset) -> Data? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat

        var result: Data?
        _ = PHImageManager.default().requestImageDataAndOrientation(
            for: phAsset,
            options: options
        ) { data, _, _, _ in
            result = data
        }
        return result
    }

    /// Decodifica e ridimensiona a 9×8 in scala di grigi a 8 bit, restituendo i
    /// campioni riga per riga. `nil` se la decodifica o il contesto grafico falliscono.
    private func grayscaleSamples(from data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else {
            return nil
        }

        let width = Self.sampleWidth
        let height = Self.sampleHeight
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return nil }

        let buffer = pixels.bindMemory(to: UInt8.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: buffer, count: width * height))
    }

    /// Costruisce i 64 bit dai campioni 9×8: per ogni riga, bit acceso quando il
    /// pixel a sinistra è più chiaro del successivo. Ordine bit deterministico.
    private static func dHash(fromGray gray: [UInt8]) -> UInt64? {
        guard gray.count == sampleWidth * sampleHeight else { return nil }
        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        for row in 0..<sampleHeight {
            let rowStart = row * sampleWidth
            for column in 0..<(sampleWidth - 1) {
                if gray[rowStart + column] > gray[rowStart + column + 1] {
                    hash |= (UInt64(1) << bitIndex)
                }
                bitIndex += 1
            }
        }
        return hash
    }
}
#endif
