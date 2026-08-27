import Foundation
import AngavuDomain

// Supporto condiviso per l'analisi immagine on-device del Data layer.
//
// Due helper riusati dagli adapter di scoring (`VisionQualityScorer` di
// `similar_photos` e `CoreImageSharpnessScorer` di `blurry_photos`), così la
// matematica della nitidezza e la lettura pixel vivono in un solo posto (niente
// duplicazione fra adapter). Tutto on-device: nessun byte lascia il device.

// MARK: - Pixel on-device (zero rete)

#if canImport(Photos)
import Photos

/// Byte dell'immagine di un asset, letti SOLO on-device (`isNetworkAccessAllowed =
/// false`): nessun fetch iCloud, nessun byte fuori dal device (00-INDEX §3). `nil`
/// se l'originale non è residente sul device o l'asset non è risolvibile.
public enum OnDeviceImageBytes {
    public static func data(for asset: LibraryAsset) -> Data? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetch.firstObject else { return nil }
        return data(for: phAsset)
    }

    /// FSE-B1 — Percorso a PHAsset già risolto: riusa l'handle batch invece di
    /// rifetchare per id. Handle non riconosciuto → fallback al fetch per id.
    /// (La taglia di decodifica resta full-res qui: il downscale è FSE-C1, ortogonale
    /// al riuso dell'handle.)
    public static func data(for handle: AssetHandle) -> Data? {
        guard let phAsset = handle.resolvedPHAsset else {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [handle.assetLocalIdentifier], options: nil)
            guard let fetched = fetch.firstObject else { return nil }
            return data(for: fetched)
        }
        return data(for: phAsset)
    }

    /// Byte on-device dell'asset già risolto (`isNetworkAccessAllowed = false`).
    private static func data(for phAsset: PHAsset) -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false   // zero rete: nessun fetch iCloud
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
}
#endif

// MARK: - Kernel di nitidezza (varianza del Laplaciano)

#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics

/// Nitidezza normalizzata 0…1 dai byte di un'immagine: varianza del Laplaciano
/// discreto su una griglia in scala di grigi, passata in una curva saturante
/// `v / (v + k)`. Deterministico e cross-Apple (CoreGraphics puro): compila e gira
/// anche sull'host macOS della CI. Il valore assoluto è un'euristica; il confronto
/// relativo (ranking dentro un cluster, soglia di sfocatura) è ciò che conta.
public enum SharpnessKernel {
    /// Lato della griglia in scala di grigi.
    public static let side = 48
    /// Costante di saturazione della normalizzazione (euristica).
    public static let saturation = 500.0

    /// Nitidezza normalizzata 0…1 dai byte di un'immagine, o `nil` se la decodifica
    /// fallisce. Percorso legacy (dati full-res → thumbnail ImageIO): resta per i
    /// chiamanti che partono dai byte. FSE-C1 preferisce il percorso `CGImage` sotto,
    /// alimentato dall'immagine già ridimensionata dal provider (leva 2).
    public static func normalizedSharpness(from data: Data) -> Double? {
        guard let gray = grayscale(from: data, side: side) else { return nil }
        return normalizedSharpness(fromGrayscale: gray)
    }

    /// FSE-C1 — Nitidezza da un `CGImage` già ridimensionato dal provider
    /// (`DownscaledImageProviding`): nessuna decodifica full-res, si ricampiona solo la
    /// griglia `side`×`side`. `nil` se il disegno in scala di grigi fallisce.
    public static func normalizedSharpness(from cgImage: CGImage) -> Double? {
        guard let gray = grayscale(from: cgImage, side: side) else { return nil }
        return normalizedSharpness(fromGrayscale: gray)
    }

    /// Varianza del Laplaciano su una griglia in scala di grigi `side`×`side`, passata
    /// nella curva saturante `v / (v + k)`. Matematica PURA, indipendente dalla
    /// sorgente (byte o `CGImage`): un solo posto per il kernel di nitidezza.
    private static func normalizedSharpness(fromGrayscale gray: [UInt8]) -> Double? {
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        for row in 1..<(side - 1) {
            for column in 1..<(side - 1) {
                let center = Double(gray[row * side + column])
                let up = Double(gray[(row - 1) * side + column])
                let down = Double(gray[(row + 1) * side + column])
                let left = Double(gray[row * side + column - 1])
                let right = Double(gray[row * side + column + 1])
                let laplacian = up + down + left + right - 4 * center
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        let variance = max(0, sumOfSquares / Double(count) - mean * mean)
        return variance / (variance + saturation)
    }

    /// Ridisegna un `CGImage` (già piccolo) a `side`×`side` in scala di grigi a 8 bit.
    private static func grayscale(from cgImage: CGImage, side: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data else { return nil }

        let buffer = pixels.bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: buffer, count: side * side))
    }

    /// Decodifica e ridimensiona a `side`×`side` in scala di grigi a 8 bit.
    private static func grayscale(from data: Data, side: Int) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(side, 64)
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else {
            return nil
        }
        return grayscale(from: thumbnail, side: side)
    }
}
#endif
