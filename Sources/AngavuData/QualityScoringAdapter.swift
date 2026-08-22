import Foundation
import AngavuDomain

// T-042 (Data) — Punteggio di qualità on-device, dietro il port `QualityScoring`.
//
// Il port è nel Domain (esagonale); qui l'adapter reale. Tre termini, tutti on-device:
//   • nitidezza  — varianza del Laplaciano su una griglia in scala di grigi (CoreGraphics
//     puro: deterministico e cross-Apple, compila anche sull'host macOS della CI);
//   • volti      — `VNDetectFaceCaptureQualityRequest` (media della qualità dei volti);
//   • aesthetics — `VNCalculateImageAestheticsScoresRequest`, SOLO iOS 18/macOS 15
//     (progressive enhancement): sotto quella soglia è `nil`, mai un requisito (AC-042-2).
//
// Il termine assente (volti non rilevati, aesthetics su iOS 17) non fa fallire il
// punteggio: `QualityScore.overall` somma i soli termini disponibili. La nitidezza è
// normalizzata a 0…1 con una curva saturante (euristica: il ranking usa il confronto
// relativo dentro un cluster; il valore assoluto non è un oracolo testato).
//
// Solo on-device: i pixel si leggono con `isNetworkAccessAllowed = false` (zero rete).

#if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision
import Photos
import ImageIO
import CoreGraphics

/// Adapter reale del punteggio di qualità. Sincrono verso il chiamante (off-main).
public struct VisionQualityScorer: QualityScoring {
    /// Lato della griglia in scala di grigi per la nitidezza.
    private static let sharpnessSide = 48
    /// Costante di saturazione della normalizzazione della nitidezza (euristica).
    private static let sharpnessSaturation = 500.0

    public init() {}

    public func score(for asset: LibraryAsset) throws -> QualityScore {
        guard let data = imageData(for: asset) else {
            // Nessun pixel on-device: punteggio esplicito e neutro, senza crash.
            return QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
        }
        let sharpnessValue = computeSharpness(from: data) ?? 0
        let vision = try computeVisionScores(from: data)
        return QualityScore(
            sharpness: sharpnessValue,
            faceQuality: vision.faceQuality,
            aesthetics: vision.aesthetics
        )
    }

    // MARK: - Vision (volti + aesthetics)

    private struct VisionScores {
        let faceQuality: Double?
        let aesthetics: Double?
    }

    private func computeVisionScores(from data: Data) throws -> VisionScores {
        let handler = VNImageRequestHandler(data: data, options: [:])
        let faceRequest = VNDetectFaceCaptureQualityRequest()

        var requests: [VNRequest] = [faceRequest]
        var aestheticsRequest: VNRequest?
        if #available(iOS 18.0, macOS 15.0, *) {
            let request = VNCalculateImageAestheticsScoresRequest()
            aestheticsRequest = request
            requests.append(request)
        }

        try handler.perform(requests)

        let faces = faceRequest.results ?? []
        let qualities = faces.compactMap { face -> Double? in
            face.faceCaptureQuality.map { Double($0) }
        }
        let faceQuality = qualities.isEmpty ? nil : qualities.reduce(0, +) / Double(qualities.count)

        var aesthetics: Double?
        if #available(iOS 18.0, macOS 15.0, *),
           let request = aestheticsRequest as? VNCalculateImageAestheticsScoresRequest,
           let observation = request.results?.first {
            aesthetics = Double(observation.overallScore)
        }

        return VisionScores(faceQuality: faceQuality, aesthetics: aesthetics)
    }

    // MARK: - Nitidezza (varianza del Laplaciano)

    /// Nitidezza normalizzata 0…1: varianza del Laplaciano discreto sulla griglia in
    /// scala di grigi, passata in una curva saturante `v / (v + k)`. `nil` se la
    /// decodifica fallisce.
    private func computeSharpness(from data: Data) -> Double? {
        let side = Self.sharpnessSide
        guard let gray = grayscale(from: data, side: side) else { return nil }

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
        return variance / (variance + Self.sharpnessSaturation)
    }

    // MARK: - Pixel on-device

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

    /// Decodifica e ridimensiona a `side`×`side` in scala di grigi a 8 bit.
    private func grayscale(from data: Data, side: Int) -> [UInt8]? {
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
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data else { return nil }

        let buffer = pixels.bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: buffer, count: side * side))
    }
}
#endif
