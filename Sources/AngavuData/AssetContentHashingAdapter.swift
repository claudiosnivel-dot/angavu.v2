import Foundation
import AngavuDomain

// T-031 (Data) — SHA-256 del contenuto di un asset via PHAssetResource.
//
// Il port `AssetContentHashing` è definito nel Domain (esagonale); qui vive
// l'adapter reale. Lo SHA-256 si calcola in streaming (CryptoKit `SHA256.update`)
// sui blocchi di dati consegnati da `PHAssetResourceManager.requestData`: niente
// caricamento dell'intera immagine in RAM (dieta low-RAM, spirito di T-004).
//
// Solo on-device: `isNetworkAccessAllowed = false` — nessun download da iCloud,
// nessun byte lascia il device (00-INDEX §3). Un originale non residente non è
// verificabile, quindi restituisce `nil`: mai dichiarato duplicato a scatola chiusa.

#if canImport(Photos) && canImport(CryptoKit)
import Photos
import CryptoKit

/// Adapter reale: legge i byte della prima risorsa dell'asset e ne calcola lo
/// SHA-256 in streaming. Sincrono verso il chiamante (che lo mette off-main),
/// come gli altri adapter del Data layer.
public struct PHAssetContentHasher: AssetContentHashing {
    public init() {}

    public func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard
            let phAsset = fetch.firstObject,
            let resource = PHAssetResource.assetResources(for: phAsset).first
        else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        // Zero rete: hashiamo solo ciò che è già sul device (nessun fetch iCloud).
        options.isNetworkAccessAllowed = false

        var hasher = SHA256()
        var receivedAnyData = false
        var requestError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        _ = PHAssetResourceManager.default().requestData(
            for: resource,
            options: options,
            dataReceivedHandler: { data in
                hasher.update(data: data)
                receivedAnyData = true
            },
            completionHandler: { error in
                requestError = error
                semaphore.signal()
            }
        )
        semaphore.wait()

        // Byte non leggibili on-device (es. in iCloud, o errore di risorsa):
        // asset non verificabile → non lo dichiariamo duplicato.
        if requestError != nil { return nil }
        guard receivedAnyData else { return nil }

        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return AssetDigest(hex)
    }
}
#endif
