import Foundation
import AngavuDomain

// T-040 (Data) — Feature print semantico via Vision, dietro il port `FeaturePrinting`.
//
// Il port è definito nel Domain (esagonale, come `AssetContentHashing`); qui vive
// l'adapter reale. Calcola `VNGenerateImageFeaturePrintRequest` per asset e la
// distanza fra due feature print con `computeDistance`. Il Domain riceve SOLO un
// `Float`: nessun tipo di Vision attraversa il confine (altitudine, 00-INDEX §1bis).
//
// Solo on-device: i pixel si leggono con `isNetworkAccessAllowed = false` — nessun
// download da iCloud, nessun byte lascia il device (00-INDEX §3). Un originale non
// residente non è calcolabile → distanza `nil`: il clustering ricadrà sul dHash.

#if canImport(Vision) && canImport(Photos)
import Vision
// FSE-C1: i pixel arrivano dal provider ridimensionato (Data), non più da PhotoKit
// diretto — `import Photos` non serve più qui (il gate `canImport(Photos)` resta,
// perché il provider di default richiede PhotoKit).

/// Adapter reale: calcola i feature print via Vision e la distanza semantica fra
/// due asset. Mantiene una cache per `id` così ogni feature print è calcolato una
/// sola volta (i confronti in un cluster sono molti). Sincrono verso il chiamante
/// (che lo mette off-main), come gli altri adapter del Data layer.
public final class VisionFeaturePrinter: FeaturePrinting {
    /// Cache id → feature print. Il valore interno `nil` memorizza "già tentato ma
    /// non calcolabile", per non ripetere la richiesta a ogni confronto.
    private var cache: [String: VNFeaturePrintObservation?] = [:]
    private let imageProvider: any DownscaledImageProviding

    /// FSE-C1: default al provider ridimensionato reale. Vision normalizza comunque il
    /// feature print a piccolo → la distanza semantica è invariante alla taglia (da
    /// verificare in FSE-C2), quindi decodificare a `.featurePrint` (≈224px) invece del
    /// full-res è puro risparmio (leva 2).
    public init(imageProvider: any DownscaledImageProviding = PHImageDownscaledProvider()) {
        self.imageProvider = imageProvider
    }

    public func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float? {
        guard
            let lhsPrint = try featurePrint(for: lhs),
            let rhsPrint = try featurePrint(for: rhs)
        else {
            return nil
        }
        var distance = Float(0)
        try lhsPrint.computeDistance(&distance, to: rhsPrint)
        return distance
    }

    /// Feature print dell'asset (con cache). `nil` se i pixel non sono leggibili
    /// on-device o Vision non produce un'osservazione.
    private func featurePrint(for asset: LibraryAsset) throws -> VNFeaturePrintObservation? {
        if let cached = cache[asset.id] {
            return cached
        }
        let handle = IdentifierAssetHandle(asset.id)
        guard
            let image = imageProvider.downscaledImage(for: handle, size: .featurePrint),
            let cgImage = image.resolvedCGImage
        else {
            cache[asset.id] = .some(nil)
            return nil
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        try handler.perform([request])
        // `results` di questa richiesta è già [VNFeaturePrintObservation]?: niente
        // cast (un `as?` qui sarebbe "always succeeds" → errore con warnings-as-errors).
        let observation = request.results?.first
        cache[asset.id] = .some(observation)
        return observation
    }
}
#endif
