import AngavuDomain

// T-070/T-071 (Data) — Scoring on-device delle foto sfocate, dietro i port del Domain.
//
// I port sono nel Domain (esagonale); qui gli adapter reali:
//   • T-070 `CoreImageSharpnessScorer` conforme a `SharpnessScoring` — nitidezza
//     via `SharpnessKernel` (varianza del Laplaciano, CoreGraphics puro);
//   • T-071 `VisionQualityScorer` (di `similar_photos`) esteso ad `AestheticsScoring`
//     — riusa l'aesthetics score iOS 18 già calcolato, come progressive enhancement.
//
// Solo on-device (zero rete). FSE-C1: la nitidezza legge dal provider ridimensionato
// (`DownscaledImageProviding`, ≈64px) invece del full-res; l'aesthetics (T-071) resta
// per ora sul percorso di `VisionQualityScorer`. Un asset senza pixel residenti →
// nitidezza `nil`: il Domain non lo dichiara mai sfocato.

// MARK: - T-070 — Adapter di nitidezza

#if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)

/// Adapter reale del punteggio di nitidezza. Sincrono verso il chiamante (off-main).
/// `nil` se i pixel non sono leggibili on-device o la decodifica fallisce: così il
/// Domain (T-070) non classifica mai come sfocato un asset non verificabile.
///
/// FSE-C1: chiede l'immagine alla taglia `.sharpness` (≈64px) al provider
/// ridimensionato, invece di decodificare l'originale full-res per un francobollo
/// (leva 2). La griglia del kernel resta `SharpnessKernel.side`: la SOGLIA di sfocatura
/// va ri-tarata/ri-dichiarata a questa taglia in FSE-C2 (non toccata qui).
public struct CoreImageSharpnessScorer: SharpnessScoring {
    private let imageProvider: any DownscaledImageProviding

    public init(imageProvider: any DownscaledImageProviding = PHImageDownscaledProvider()) {
        self.imageProvider = imageProvider
    }

    public func sharpness(for asset: LibraryAsset) throws -> Double? {
        let handle = IdentifierAssetHandle(asset.id)
        guard
            let image = imageProvider.downscaledImage(for: handle, size: .sharpness),
            let cgImage = image.resolvedCGImage
        else {
            return nil   // non residente / non producibile → mai un falso "sfocato"
        }
        return SharpnessKernel.normalizedSharpness(from: cgImage)
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
