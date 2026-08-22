import AngavuDomain

// T-070/T-071 (Data) — Scoring on-device delle foto sfocate, dietro i port del Domain.
//
// I port sono nel Domain (esagonale); qui gli adapter reali:
//   • T-070 `CoreImageSharpnessScorer` conforme a `SharpnessScoring` — nitidezza
//     via `SharpnessKernel` (varianza del Laplaciano, CoreGraphics puro);
//   • T-071 `VisionQualityScorer` (di `similar_photos`) esteso ad `AestheticsScoring`
//     — riusa l'aesthetics score iOS 18 già calcolato, come progressive enhancement.
//
// Solo on-device: i pixel si leggono con `OnDeviceImageBytes` (zero rete). Un asset
// senza pixel residenti → nitidezza `nil`: il Domain non lo dichiara mai sfocato.

// MARK: - T-070 — Adapter di nitidezza

#if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)

/// Adapter reale del punteggio di nitidezza. Sincrono verso il chiamante (off-main).
/// `nil` se i pixel non sono leggibili on-device o la decodifica fallisce: così il
/// Domain (T-070) non classifica mai come sfocato un asset non verificabile.
public struct CoreImageSharpnessScorer: SharpnessScoring {
    public init() {}

    public func sharpness(for asset: LibraryAsset) throws -> Double? {
        guard let data = OnDeviceImageBytes.data(for: asset) else { return nil }
        return SharpnessKernel.normalizedSharpness(from: data)
    }
}
#endif

// MARK: - T-071 — Aesthetics come progressive enhancement (reuse di similar_photos)

#if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)

/// `VisionQualityScorer` (introdotto da `similar_photos`, T-042) calcola già
/// l'aesthetics score iOS 18 dentro `QualityScore`. Qui lo si espone come port
/// `AestheticsScoring` per `blurry_photos` (T-071): riuso puro, nessun ricalcolo di
/// concetti. Su iOS 17 `QualityScore.aesthetics` è `nil` → l'assessment del Domain
/// degrada alla sola nitidezza, marcato "senza aesthetics" (AC-071-2).
extension VisionQualityScorer: AestheticsScoring {
    public func aesthetics(for asset: LibraryAsset) throws -> Double? {
        try score(for: asset).aesthetics
    }
}
#endif
