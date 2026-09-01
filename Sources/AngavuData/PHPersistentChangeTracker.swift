import AngavuDomain
import Foundation

// FSE-K2 (Data) — Adapter PhotoKit del tracciamento PERSISTENTE dei cambi (iOS 16+).
//
// `PHPhotoLibrary.currentChangeToken` è un token opaco (NSSecureCoding) che sopravvive
// ai lanci; `fetchPersistentChanges(since:)` restituisce la storia dei cambi da quel
// token, da cui si estraggono gli id `inserted/updated/deleted` degli asset. Mappa gli
// errori PhotoKit sull'esito di dominio: `persistentChangeTokenExpired` → `.expired`
// (serve una scansione completa), `persistentChangeDetailsUnavailable` → `.unavailable`
// (nessuna prova). Ogni altro errore, o un token non decodificabile, è `.unavailable`:
// mai un delta vuoto fabbricato. Solo on-device, zero rete; nessuna usage-description
// nuova (stessa autorizzazione Foto della scansione). Apple-only, guardato.

#if canImport(Photos)
import Photos

public final class PHPersistentChangeTracker: LibraryChangeTracking {
    public init() {}

    public func currentToken() -> Data? {
        Self.encode(PHPhotoLibrary.shared().currentChangeToken)
    }

    public func changes(since token: Data) -> LibraryChangeOutcome {
        guard let since = Self.decode(token) else { return .unavailable }
        do {
            let history = try PHPhotoLibrary.shared().fetchPersistentChanges(since: since)
            var inserted = Set<String>()
            var updated = Set<String>()
            var deleted = Set<String>()
            for change in history {
                let details = try change.changeDetails(for: .asset)
                inserted.formUnion(details.insertedLocalIdentifiers)
                updated.formUnion(details.updatedLocalIdentifiers)
                deleted.formUnion(details.deletedLocalIdentifiers)
            }
            return .delta(LibraryChangeDelta(inserted: inserted, updated: updated, deleted: deleted))
        } catch let error as PHPhotosError {
            switch error.code {
            case .persistentChangeTokenExpired: return .expired
            default: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    /// Serializzazione opaca del token (NSSecureCoding → Data): è ciò che viene
    /// persistito accanto ai `CategoryResultRecord`.
    static func encode(_ token: PHPersistentChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func decode(_ data: Data) -> PHPersistentChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }
}
#endif
