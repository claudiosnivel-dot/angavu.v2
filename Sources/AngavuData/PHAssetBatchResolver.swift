import Foundation
import AngavuDomain

// FSE-B1 (Data) — Risolutore batch reale dei PHAsset dietro il port
// `AssetHandleResolving` (Domain).
//
// Fetcha i `PHAsset` in BLOCCHI (`PHAsset.fetchAssets(withLocalIdentifiers:)` su un
// chunk, non su un singolo id) e li avvolge in `PHAssetHandle` opachi, riusabili da
// tutti gli adapter (byte, residenza, pixel, feature print) per la durata della
// scansione. Elimina i 25k×N fetch singoli della diagnosi (FAST-SCAN-ENGINE-PLAN §1.1).
//
// Onestà/privacy: nessun accesso rete — la risoluzione opera su identificatori locali
// (nessun byte lascia il device, 00-INDEX §3). La mappa viva è rilasciata a fine
// scansione col suo `ResolvedAssetHandles` (nessuna ritenzione oltre l'uso).
//
// Copertura dichiarata (L-COL-006): adapter Apple-only → compilato in CI, runtime sul
// device NON coperto (richiede una libreria PhotoKit reale). L'oracolo della logica di
// batch/chunking/riuso è nei test di Domain/Features con handle fake.

#if canImport(Photos)
import Photos

/// Handle opaco concreto: incapsula un `PHAsset` già risolto. Gli adapter del Data
/// lo riconoscono (via `resolvedPHAsset`) per lavorare sull'asset senza rifetcharlo.
public final class PHAssetHandle: AssetHandle {
    public let asset: PHAsset

    public init(_ asset: PHAsset) {
        self.asset = asset
    }

    public var assetLocalIdentifier: String { asset.localIdentifier }
}

/// Adapter reale: risolve i `PHAsset` in batch per chunk e li avvolge in handle
/// riusabili. Il chunking e l'assemblaggio vivono nel Domain
/// (`BatchAssetHandleResolver`); qui resta solo il fetch di piattaforma.
public struct PHAssetBatchResolver: AssetHandleResolving {
    private let base: BatchAssetHandleResolver

    /// - Parameter chunkSize: id per blocco di fetch (default 256): abbastanza ampio
    ///   da ammortizzare l'overhead di query, abbastanza limitato da non tenere viva
    ///   l'intera libreria in un solo `PHFetchResult`.
    public init(chunkSize: Int = 256) {
        self.base = BatchAssetHandleResolver(chunkSize: chunkSize) { chunk in
            Self.resolveChunk(chunk)
        }
    }

    public func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles {
        base.resolve(localIdentifiers: localIdentifiers)
    }

    /// Fetch di un singolo blocco: una chiamata `fetchAssets` per l'intero chunk.
    /// Gli id inesistenti non compaiono nel `PHFetchResult` → sono naturalmente
    /// omessi dagli handle (mai un placeholder finto).
    private static func resolveChunk(_ identifiers: [String]) -> [AssetHandle] {
        guard !identifiers.isEmpty else { return [] }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var handles: [AssetHandle] = []
        handles.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            handles.append(PHAssetHandle(asset))
        }
        return handles
    }
}

/// Estrae il `PHAsset` da un handle opaco risolto dal resolver di FSE-B1. `nil` se
/// l'handle non proviene da questo Data layer (mai un cast forzato): l'adapter
/// ricade allora sul proprio percorso di fetch per id.
extension AssetHandle {
    var resolvedPHAsset: PHAsset? {
        (self as? PHAssetHandle)?.asset
    }
}
#endif
