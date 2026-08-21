import AngavuDomain

// T-011 (Data) — Enumerazione dei PHAsset.
//
// L'adapter è l'UNICO punto che tocca Photos; produce `RawEnumeratedAsset` (valori
// grezzi puri) che il Domain mappa in `LibraryAsset`. Guardato da `canImport(Photos)`.

/// Sorgente di asset grezzi. I test la sostituiscono con un fake che restituisce
/// item noti.
public protocol PhotoAssetEnumerating {
    /// Enumera tutti gli asset (foto e video) come item grezzi, in un solo passaggio.
    func enumerateRawAssets() -> [RawEnumeratedAsset]
}

#if canImport(Photos)
import Photos

/// Adapter reale su PhotoKit.
public struct SystemPhotoAssetEnumerator: PhotoAssetEnumerating {
    public init() {}

    public func enumerateRawAssets() -> [RawEnumeratedAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: options)

        var items: [RawEnumeratedAsset] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(
                RawEnumeratedAsset(
                    localIdentifier: asset.localIdentifier,
                    mediaTypeRawValue: asset.mediaType.rawValue,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: asset.creationDate,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
                )
            )
        }
        return items
    }
}
#endif
