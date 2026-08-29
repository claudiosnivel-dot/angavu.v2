import Foundation
import AngavuDomain

// T-042 (Data) — Punteggio di qualità on-device, dietro il port `QualityScoring`.
//
// Il port è nel Domain (esagonale); qui l'adapter reale. Tre termini, tutti on-device:
//   • nitidezza  — `SharpnessKernel` (varianza del Laplaciano, CoreGraphics puro:
//     deterministico e cross-Apple, condiviso con `CoreImageSharpnessScorer` di
//     `blurry_photos` — un solo posto per la matematica della nitidezza);
//   • volti      — `VNDetectFaceCaptureQualityRequest` (media della qualità dei volti);
//   • aesthetics — `VNCalculateImageAestheticsScoresRequest`, SOLO iOS 18/macOS 15
//     (progressive enhancement): sotto quella soglia è `nil`, mai un requisito (AC-042-2).
//
// Il termine assente (volti non rilevati, aesthetics su iOS 17) non fa fallire il
// punteggio: `QualityScore.overall` somma i soli termini disponibili.
//
// FSE-I2: i pixel arrivano dal provider RIDIMENSIONATO (`DownscaledImageProviding`,
// ≈224px `.featurePrint`) dentro un `autoreleasepool`, NON più dall'originale full-res
// (`OnDeviceImageBytes.data`). Il keep-best dei simili chiama questo scorer una volta per
// membro di cluster: a piena risoluzione erano una decodifica pesante per foto → il
// freeze di ~1 min osservato al 2° device-test alla fase «simili». La qualità è RELATIVA
// (ranking dentro un cluster, mai un valore assoluto pubblicato), quindi ≈224px basta.
// `isNetworkAccessAllowed = false` resta invariante (miniatura on-device, zero rete):
// un originale solo in iCloud → `nil` → punteggio neutro esplicito, mai un download.

#if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision
import CoreGraphics

/// Adapter reale del punteggio di qualità. Sincrono verso il chiamante (off-main).
public struct VisionQualityScorer: QualityScoring {
    private let imageProvider: any DownscaledImageProviding

    /// FSE-I2: default al provider ridimensionato reale, come nitidezza (`.sharpness`)
    /// e feature print (`.featurePrint`). Iniettabile per l'oracolo della taglia.
    public init(imageProvider: any DownscaledImageProviding = PHImageDownscaledProvider()) {
        self.imageProvider = imageProvider
    }

    public func score(for asset: LibraryAsset) throws -> QualityScore {
        let handle = IdentifierAssetHandle(asset.id)
        // Un solo decode piccolo (≈224px) per membro, rilasciato SUBITO: `autoreleasepool`
        // impedisce l'accumulo dei temporanei di decodifica/Vision fra un membro e il
        // successivo (dieta memoria del keep-best, coerente con FSE-C1/H3).
        return try autoreleasepool {
            guard
                let image = imageProvider.downscaledImage(for: handle, size: .featurePrint),
                let cgImage = image.resolvedCGImage
            else {
                // Nessun pixel on-device (originale solo in iCloud / decodifica fallita):
                // punteggio esplicito e neutro, senza crash e senza valore fabbricato.
                return QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
            }
            let sharpnessValue = SharpnessKernel.normalizedSharpness(from: cgImage) ?? 0
            let vision = try computeVisionScores(from: cgImage)
            return QualityScore(
                sharpness: sharpnessValue,
                faceQuality: vision.faceQuality,
                aesthetics: vision.aesthetics
            )
        }
    }

    // MARK: - Vision (volti + aesthetics)

    private struct VisionScores {
        let faceQuality: Double?
        let aesthetics: Double?
    }

    private func computeVisionScores(from cgImage: CGImage) throws -> VisionScores {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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
}
#endif
