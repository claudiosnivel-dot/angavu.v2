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
import Photos

/// Adapter reale: calcola i feature print via Vision e la distanza semantica fra
/// due asset. Mantiene una cache per `id` così ogni feature print è calcolato una
/// sola volta (i confronti in un cluster sono molti). Sincrono verso il chiamante
/// (che lo mette off-main), come gli altri adapter del Data layer.
public final class VisionFeaturePrinter: FeaturePrinting {
    /// Cache id → feature print. Il valore interno `nil` memorizza "già tentato ma
    /// non calcolabile", per non ripetere la richiesta a ogni confronto.
    private var cache: [String: VNFeaturePrintObservation?] = [:]

    public init() {}

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
        guard let data = imageData(for: asset) else {
            cache[asset.id] = .some(nil)
            return nil
        }
        let handler = VNImageRequestHandler(data: data, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        try handler.perform([request])
        // `results` di questa richiesta è già [VNFeaturePrintObservation]?: niente
        // cast (un `as?` qui sarebbe "always succeeds" → errore con warnings-as-errors).
        let observation = request.results?.first
        cache[asset.id] = .some(observation)
        return observation
    }

    /// Byte dell'immagine, letti SOLO on-device (zero rete). `nil` se l'originale
    /// non è residente sul device o l'asset non è risolvibile.
    private func imageData(for asset: LibraryAsset) -> Data? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetch.firstObject else { return nil }

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
