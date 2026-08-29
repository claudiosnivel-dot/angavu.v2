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
    ///
    /// FSE-H2 — Questo è il percorso LEGACY che decodifica i byte originali (full-res)
    /// prima di ridurli: resta come alternativa, ma il percorso di produzione è ora quello
    /// C1 (`dHash(fromDownscaled:)`), che parte dalla miniatura piccola senza mai
    /// materializzare l'originale intero (leva 2).
    public func dHash(for asset: LibraryAsset) -> UInt64? {
        guard
            let data = imageData(for: asset),
            let gray = grayscaleSamples(from: data)
        else {
            return nil
        }
        return Self.dHash(fromGray: gray)
    }

    /// FSE-H2 — dHash a 64 bit da un'immagine GIÀ ridimensionata (miniatura C1,
    /// `.pixels(64)`): il percorso di produzione. Nessuna decodifica full-res — riduce a
    /// 9×8 grigi la miniatura piccola e ne calcola i 64 bit. `nil` se l'immagine non
    /// proviene da questo Data layer o il contesto grafico fallisce (mai un valore
    /// fabbricato). Delega la matematica dei bit alla STESSA `dHash(fromGray:)` del
    /// percorso legacy: una sola fonte di verità sull'algoritmo.
    public func dHash(fromDownscaled image: DownscaledImage) -> UInt64? {
        guard
            let cgImage = image.resolvedCGImage,
            let gray = grayscaleSamples(fromCGImage: cgImage)
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

    /// Decodifica i byte, ne fa una miniatura e la riduce a 9×8 grigi (percorso legacy).
    /// `nil` se la decodifica fallisce.
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
        return grayscaleSamples(fromCGImage: thumbnail)
    }

    /// Ridimensiona a 9×8 in scala di grigi a 8 bit un `CGImage` (già piccolo),
    /// restituendo i campioni riga per riga. `nil` se il contesto grafico fallisce.
    /// Condiviso dal percorso legacy (miniatura da byte) e da quello C1 (miniatura
    /// ridimensionata dal provider): una sola riduzione, un solo ordine dei bit.
    private func grayscaleSamples(fromCGImage cgImage: CGImage) -> [UInt8]? {
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
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
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

/// FSE-H2 — Adapter reale del port `AssetPerceptualHashing` che riusa la miniatura C1
/// (`.pixels(64)`, `isNetworkAccessAllowed = false` nel provider) invece di decodificare
/// l'originale full-res. Ogni calcolo gira dentro un `autoreleasepool`: i temporanei
/// della decodifica di quella foto si rilasciano PRIMA della successiva (dieta memoria
/// per-foto, come il motore concorrente FSE-D1/H3), così comporre i dHash su tutta la
/// libreria trattiene solo `UInt64`, mai immagini. La matematica del dHash è delegata a
/// `PerceptualDHasher` (una sola fonte di verità sull'algoritmo).
///
/// Onestà/privacy (§6): un originale solo in iCloud con rete disabilitata → il provider
/// restituisce `nil` → dHash `nil` (mai un download, mai un valore fabbricato). Adapter
/// Apple-only → compilato in CI, il calcolo reale dai pixel è device-only (AC-FSE-H2-3,
/// §7): la LOGICA di composizione/clustering è provata dagli oracoli con provider fake.
public struct DownscaledPerceptualHasher: AssetPerceptualHashing {
    private let imageProvider: any DownscaledImageProviding
    private let hasher = PerceptualDHasher()

    /// FSE-C1: default al provider ridimensionato reale (miniatura piccola, zero rete).
    public init(imageProvider: any DownscaledImageProviding = PHImageDownscaledProvider()) {
        self.imageProvider = imageProvider
    }

    public func dHash(for asset: LibraryAsset) -> UInt64? {
        autoreleasepool {
            let handle = IdentifierAssetHandle(asset.id)
            guard let image = imageProvider.downscaledImage(for: handle, size: .pixels(64)) else {
                return nil
            }
            return hasher.dHash(fromDownscaled: image)
        }
    }
}
#endif
