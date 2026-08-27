import Foundation

// FSE-B1 (Domain) — Port di risoluzione batch dei PHAsset (leva 1).
//
// Oggi ogni adapter risolve il proprio asset con `PHAsset.fetchAssets(
// withLocalIdentifiers: [id])` UNO PER ASSET, e lo stesso asset è rifetchato da
// più adapter (byte, residenza, pixel, feature print) nella stessa scansione:
// su ~25k foto sono 25k×N invocazioni singole, ognuna che paga l'overhead di
// query del Photos framework (FAST-SCAN-ENGINE-PLAN §1.1).
//
// Questo port sposta la risoluzione in BATCH e la rende RIUSABILE: il `PHAsset` è
// fetchato una sola volta (in blocchi) e messo in una mappa `id → handle` viva per
// la durata della scansione; gli adapter chiedono l'handle già risolto invece di
// rifetcharlo.
//
// Altitudine (00-INDEX §1bis): il Domain resta puro. L'handle è OPACO — un
// riferimento senza alcun tipo di Photos che l'attraversa; il tipo concreto
// (`PHAssetHandle`) vive nel Data. Qui vivono il contratto, la logica di chunking
// (pura, testabile su Linux) e un orchestratore riusabile.

/// Riferimento opaco a un asset di sistema già risolto, condivisibile fra adapter.
///
/// È `AnyObject` di proposito: l'identità del riferimento è ciò che prova il riuso
/// (lo stesso handle passa a byte/residenza/pixel senza un nuovo fetch). Il tipo
/// concreto (che incapsula un `PHAsset`) vive nel Data — nessun tipo di Photos
/// attraversa questo confine.
public protocol AssetHandle: AnyObject {
    /// Identificatore locale stabile dell'asset (in PhotoKit: `PHAsset.localIdentifier`).
    var assetLocalIdentifier: String { get }
}

/// Mappa `id → handle` prodotta da una risoluzione, viva per la durata dell'uso.
///
/// Valore immutabile che incapsula riferimenti agli handle: copiarla condivide gli
/// stessi handle (nessun refetch). Un id assente restituisce `nil` — mai un
/// placeholder finto (un asset inesistente resta assente, coerente col manifesto).
public struct ResolvedAssetHandles {
    private let handlesByID: [String: AssetHandle]

    /// Costruisce la mappa dagli handle risolti, indicizzati per identificatore.
    /// A parità di id l'ultimo vince (deterministico); nessun handle è duplicato in
    /// output perché la mappa è per chiave.
    public init(_ handles: [AssetHandle]) {
        var byID: [String: AssetHandle] = [:]
        byID.reserveCapacity(handles.count)
        for handle in handles {
            byID[handle.assetLocalIdentifier] = handle
        }
        self.handlesByID = byID
    }

    /// Handle già risolto per l'id, o `nil` se l'asset non è stato risolto (assente
    /// dalla libreria): mai un placeholder finto.
    public func handle(for localIdentifier: String) -> AssetHandle? {
        handlesByID[localIdentifier]
    }

    /// Numero di asset effettivamente risolti (≤ numero di id richiesti: gli
    /// inesistenti non compaiono).
    public var count: Int { handlesByID.count }

    /// Identificatori risolti (per ispezione/test). Ordine non garantito.
    public var resolvedIdentifiers: Set<String> { Set(handlesByID.keys) }
}

/// Handle minimale che porta SOLO l'identificatore locale, senza un asset di sistema
/// risolto. Serve da bridge dove un adapter ha un `LibraryAsset` (quindi un id) ma non
/// ancora la mappa batch condivisa: il consumatore reale (es. il provider di immagine
/// ridimensionata, FSE-C1) non riconosce questo handle → ricade sul proprio fetch per
/// id, comportamento identico a oggi. Il riuso senza refetch arriva quando FSE-F caba
/// la `ResolvedAssetHandles` attraverso le fasi.
public final class IdentifierAssetHandle: AssetHandle {
    public let assetLocalIdentifier: String
    public init(_ assetLocalIdentifier: String) {
        self.assetLocalIdentifier = assetLocalIdentifier
    }
}

/// Risolve un elenco di identificatori locali in handle riusabili, in batch.
public protocol AssetHandleResolving {
    /// Risolve gli id in una mappa `id → handle`. Gli id inesistenti sono
    /// semplicemente assenti dal risultato (mai un crash, mai un placeholder).
    func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles
}

/// Suddivisione deterministica di un elenco di identificatori in blocchi.
///
/// Pura e testabile su Linux: è l'oracolo di AC-FSE-B1-3 (copertura totale, nessun
/// duplicato, nessun buco). Un `PHFetchResult` batch enorme non è desiderabile
/// (memoria); il chunking limita la finestra viva senza perdere id.
public enum AssetIdentifierBatches {
    /// Spezza `identifiers` in blocchi di al più `chunkSize`, preservando l'ordine e
    /// coprendo ogni id ESATTAMENTE una volta.
    ///
    /// - `chunkSize` ≤ 0 è trattato come 1 (nessun blocco vuoto, nessun ciclo infinito).
    /// - Un elenco vuoto restituisce nessun blocco.
    public static func chunked(_ identifiers: [String], chunkSize: Int) -> [[String]] {
        let size = max(1, chunkSize)
        guard !identifiers.isEmpty else { return [] }
        var chunks: [[String]] = []
        var start = 0
        while start < identifiers.count {
            let end = min(start + size, identifiers.count)
            chunks.append(Array(identifiers[start..<end]))
            start = end
        }
        return chunks
    }
}

/// Orchestratore puro e riusabile: applica il chunking e delega la risoluzione di
/// ogni blocco a una closure (che nel Data reale fetcha i `PHAsset` in batch),
/// assemblando gli handle in un'unica `ResolvedAssetHandles`.
///
/// Tenendo il chunking + l'assemblaggio nel Domain, l'adapter reale resta minimale
/// (solo il fetch di piattaforma) e la logica è provata da un oracolo CI con una
/// closure-spia — senza device.
public struct BatchAssetHandleResolver: AssetHandleResolving {
    private let chunkSize: Int
    private let resolveChunk: ([String]) -> [AssetHandle]

    /// - Parameters:
    ///   - chunkSize: massimo id per blocco di fetch (default 256, ampio ma limitato).
    ///   - resolveChunk: risolve un blocco di id negli handle esistenti (gli
    ///     inesistenti sono omessi dal risultato del blocco).
    public init(chunkSize: Int = 256, resolveChunk: @escaping ([String]) -> [AssetHandle]) {
        self.chunkSize = chunkSize
        self.resolveChunk = resolveChunk
    }

    public func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles {
        var handles: [AssetHandle] = []
        for chunk in AssetIdentifierBatches.chunked(localIdentifiers, chunkSize: chunkSize) {
            handles.append(contentsOf: resolveChunk(chunk))
        }
        return ResolvedAssetHandles(handles)
    }
}

/// Null-object: nessun asset è risolvibile (grafi parziali/di test, o build senza
/// PhotoKit). Coerente con `NoContentHasher`/`AssumeResidentResidencyProbe`: mai un
/// handle finto, la mappa resta vuota finché `live()` non cabla l'adapter reale.
public struct EmptyAssetHandleResolver: AssetHandleResolving {
    public init() {}
    public func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles {
        ResolvedAssetHandles([])
    }
}
