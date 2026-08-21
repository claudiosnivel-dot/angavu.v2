import AngavuDomain

// T-051 (Data) — Eliminazione via deleteAssets verso "Eliminati di recente".
//
// L'eliminazione confermata (gate anteprima di T-050 già superato nel Domain)
// passa da `PHAssetChangeRequest.deleteAssets` su un batch: UN SOLO alert di
// sistema per batch, nessun loop per-asset. L'esito manda gli asset in "Eliminati
// di recente" (recupero di sistema ~30 gg): la rete di sicurezza è fornita da iOS,
// non serve ricostruire un cestino. Su success i record vengono rimossi dall'indice;
// su annullamento dell'alert l'indice non viene toccato.

/// Esito dell'eliminazione di sistema di un batch.
public enum BatchDeletionResult: Equatable, Sendable {
    /// `deleteAssets` riuscita: gli asset sono in "Eliminati di recente".
    case success
    /// L'utente ha annullato l'alert di sistema: nulla è stato eliminato.
    case cancelled
    /// Errore di sistema diverso dall'annullamento.
    case failed(reason: String)
}

/// Adapter che elimina un batch di asset con un solo alert di sistema. I test lo
/// sostituiscono con un fake che registra le chiamate.
public protocol AssetDeleting {
    /// Elimina in blocco gli asset con gli id dati. Una sola richiesta di sistema.
    func delete(ids: [String]) async -> BatchDeletionResult
}

/// Coordina eliminazione di sistema e aggiornamento dell'indice: rimuove i record
/// dall'indice SOLO se l'eliminazione è andata a buon fine; su `cancelled`/`failed`
/// l'indice resta invariato (coerenza con quel che è davvero accaduto sul device).
public struct BatchDeletionCoordinator {
    private let deleter: AssetDeleting
    private let index: AssetIndexWriting

    public init(deleter: AssetDeleting, index: AssetIndexWriting) {
        self.deleter = deleter
        self.index = index
    }

    /// Esegue l'eliminazione del batch e allinea l'indice all'esito reale.
    @discardableResult
    public func delete(ids: [String]) async throws -> BatchDeletionResult {
        let result = await deleter.delete(ids: ids)
        if case .success = result {
            try index.remove(ids: ids)
        }
        return result
    }
}

#if canImport(Photos)
import Photos

/// Adapter reale su PhotoKit. `deleteAssets` su tutto il batch = un solo alert.
public struct SystemAssetDeleter: AssetDeleting {
    public init() {}

    public func delete(ids: [String]) async -> BatchDeletionResult {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return .success } // niente da eliminare: no-op onesto

        do {
            try await PHPhotoLibrary.shared().performChanges {
                // Un'unica richiesta per l'intero batch: un solo alert di sistema.
                PHAssetChangeRequest.deleteAssets(fetch)
            }
            return .success
        } catch let error as PHPhotosError where error.code == .userCancelled {
            // L'utente ha annullato l'alert: nessuna eliminazione.
            return .cancelled
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }
    }
}
#endif
