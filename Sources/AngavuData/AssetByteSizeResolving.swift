import AngavuDomain

// T-014 (Data) — Dimensione in byte reale via PHAssetResource.
//
// La dimensione esatta non è esposta da un'API pubblica tipizzata: si legge la
// chiave `fileSize` di `PHAssetResource` (Int64 opzionale). Quando manca, si
// degrada a una stima marcata `estimated` dal `ByteSizePolicy` del Domain, mai
// spacciata per esatta.

/// Risolve la dimensione di un asset a partire dal suo identificatore locale.
public protocol AssetByteSizeResolving {
    /// Dimensione dell'asset, esatta o esplicitamente stimata.
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize
}

#if canImport(Photos)
import Photos

/// Adapter reale: somma le dimensioni esatte delle risorse dell'asset; se nessuna
/// espone `fileSize`, restituisce la stima marcata.
public struct PHAssetByteSizeResolver: AssetByteSizeResolving {
    public init() {}

    public func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else {
            return ByteSizePolicy.resolve(RawResourceSize(exactBytes: nil, fallbackEstimate: fallbackEstimate))
        }
        return byteSize(for: asset, fallbackEstimate: fallbackEstimate)
    }

    /// FSE-B1 — Percorso a PHAsset già risolto: riusa l'handle prodotto in batch dal
    /// `PHAssetBatchResolver` invece di rifetchare per id. Se l'handle non è
    /// riconosciuto (non proviene da questo Data), ricade sul fetch per id (nessuna
    /// perdita di correttezza, solo il costo di un fetch in più).
    public func byteSize(for handle: AssetHandle, fallbackEstimate: Int64) -> ByteSize {
        guard let asset = handle.resolvedPHAsset else {
            return byteSize(forLocalIdentifier: handle.assetLocalIdentifier, fallbackEstimate: fallbackEstimate)
        }
        return byteSize(for: asset, fallbackEstimate: fallbackEstimate)
    }

    /// Somma i `fileSize` esatti delle risorse dell'asset; se nessuna li espone,
    /// restituisce la stima marcata. Nessun tipo di Photos attraversa il confine.
    private func byteSize(for asset: PHAsset, fallbackEstimate: Int64) -> ByteSize {
        var total: Int64 = 0
        var sawExact = false
        for resource in PHAssetResource.assetResources(for: asset) {
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
                sawExact = true
            }
        }

        let raw = RawResourceSize(exactBytes: sawExact ? total : nil, fallbackEstimate: fallbackEstimate)
        return ByteSizePolicy.resolve(raw)
    }
}
#endif
