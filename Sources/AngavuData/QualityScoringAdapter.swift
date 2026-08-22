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
// Solo on-device: i pixel si leggono con `OnDeviceImageBytes` (zero rete).

#if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision

/// Adapter reale del punteggio di qualità. Sincrono verso il chiamante (off-main).
public struct VisionQualityScorer: QualityScoring {
    public init() {}

    public func score(for asset: LibraryAsset) throws -> QualityScore {
        guard let data = OnDeviceImageBytes.data(for: asset) else {
            // Nessun pixel on-device: punteggio esplicito e neutro, senza crash.
            return QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
        }
        let sharpnessValue = SharpnessKernel.normalizedSharpness(from: data) ?? 0
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
}
#endif
