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
public final class VisionFeaturePrinter: FeaturePrinting, FeaturePrintVectorProducing {
    /// Cache id → feature print. Il valore interno `nil` memorizza "già tentato ma
    /// non calcolabile", per non ripetere la richiesta a ogni confronto.
    /// FSE-D2 — protetta da lock: sotto esecuzione CONCORRENTE (pre-warm parallelo dei
    /// feature print) più worker leggono/scrivono la mappa. La correttezza del
    /// dizionario vive qui; la validazione a runtime è on-device con Thread Sanitizer (§7).
    private var cache: [String: VNFeaturePrintObservation?] = [:]
    private let cacheLock = NSLock()
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

    /// FSE-E3 — Produce il vettore feature print SERIALIZZATO (bytes opachi), così la
    /// cache dei derivati (FSE-E2) può persisterlo e riusarlo fra scansioni senza
    /// ricalcolare Vision. Il Domain vede solo `Data`: nessun tipo di Vision attraversa
    /// il confine (altitudine, 00-INDEX §1bis). `nil` se l'asset non ha un feature print
    /// calcolabile on-device (mai un vettore fabbricato). Riusa la cache d'osservazioni
    /// in memoria, quindi serializza al più una volta per asset per sessione.
    public func vector(for asset: LibraryAsset) throws -> Data? {
        guard let observation = try featurePrint(for: asset) else { return nil }
        return try NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: true
        )
    }

    /// Feature print dell'asset (con cache thread-safe). `nil` se i pixel non sono
    /// leggibili on-device o Vision non produce un'osservazione.
    private func featurePrint(for asset: LibraryAsset) throws -> VNFeaturePrintObservation? {
        cacheLock.lock()
        let cached = cache[asset.id]
        cacheLock.unlock()
        if let cached {
            return cached
        }

        // Calcolo Vision FUORI dal lock: serializzarlo annullerebbe il parallelismo di
        // FSE-D2. Due worker sullo stesso asset possono calcolare entrambi nella
        // finestra fra miss e store — innocuo (stesso valore deterministico, l'ultimo
        // scrive). Un `throw` propaga senza scrivere in cache (si ritenta, come prima).
        let observation = try computeFeaturePrint(for: asset)

        cacheLock.lock()
        cache[asset.id] = .some(observation)
        cacheLock.unlock()
        return observation
    }

    /// Calcolo puro del feature print (nessun accesso alla cache): isolato così il
    /// lavoro Vision resta fuori dal lock.
    private func computeFeaturePrint(for asset: LibraryAsset) throws -> VNFeaturePrintObservation? {
        let handle = IdentifierAssetHandle(asset.id)
        guard
            let image = imageProvider.downscaledImage(for: handle, size: .featurePrint),
            let cgImage = image.resolvedCGImage
        else {
            return nil
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        try handler.perform([request])
        // `results` di questa richiesta è già [VNFeaturePrintObservation]?: niente
        // cast (un `as?` qui sarebbe "always succeeds" → errore con warnings-as-errors).
        return request.results?.first
    }
}
#endif
