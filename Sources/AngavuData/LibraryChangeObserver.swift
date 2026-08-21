import AngavuDomain

// T-013 (Data) — Osservazione dei cambi libreria e traduzione in `IndexDelta`.
//
// La REGOLA di applicazione del delta è pura e vive nel Domain
// (`IncrementalIndex.apply`, testata da IncrementalIndexDeltaTests). Qui c'è solo
// il glue PhotoKit: `PHPhotoLibraryChangeObserver` → change-set → `IndexDelta` di
// dominio, che poi il chiamante applica all'indice SwiftData in modo incrementale
// (upsert per `added`/`changed`, remove per `removed`). Apple-only, guardato.

/// Riceve i delta tradotti dai cambi libreria.
public protocol LibraryChangeSink: AnyObject {
    func didObserve(_ delta: IndexDelta)
}

#if canImport(Photos)
import Photos

/// Osservatore che mantiene il `PHFetchResult` corrente, calcola i delta a ogni
/// cambio e li inoltra al sink. Va registrato/deregistrato dal chiamante.
public final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private var fetchResult: PHFetchResult<PHAsset>
    private weak var sink: LibraryChangeSink?

    public init(initialFetch: PHFetchResult<PHAsset>, sink: LibraryChangeSink) {
        self.fetchResult = initialFetch
        self.sink = sink
    }

    public func register() { PHPhotoLibrary.shared().register(self) }
    public func unregister() { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let details = changeInstance.changeDetails(for: fetchResult) else { return }
        // Aggiorna il fetch corrente per il prossimo confronto.
        fetchResult = details.fetchResultAfterChanges

        let added = details.insertedObjects.map(Self.map)
        let changed = details.changedObjects.map(Self.map)
        let removed = details.removedObjects.map { $0.localIdentifier }

        // Nessun delta vuoto inoltrato: evita risvegli inutili a valle.
        guard !(added.isEmpty && changed.isEmpty && removed.isEmpty) else { return }
        sink?.didObserve(IndexDelta(added: added, removed: removed, changed: changed))
    }

    /// Riusa il mapping puro del Domain per restare coerente con l'enumerazione.
    private static func map(_ asset: PHAsset) -> LibraryAsset {
        let raw = RawEnumeratedAsset(
            localIdentifier: asset.localIdentifier,
            mediaTypeRawValue: asset.mediaType.rawValue,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
        // Il change-set contiene solo foto/video già indicizzabili; in caso di tipo
        // non gestito si ricade su un asset foto neutro (mai un crash sul glue).
        return LibraryAssetMapper.map(raw)
            ?? LibraryAsset(
                id: asset.localIdentifier,
                kind: .photo,
                pixelSize: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight),
                creationDate: asset.creationDate,
                subtypes: []
            )
    }
}
#endif
