import Foundation

// T-013 — Delta incrementale della libreria e sua applicazione a uno snapshot.
//
// La traduzione di un change-set PhotoKit in delta di dominio (added/removed/
// changed) vive nell'adapter del Data layer; QUI c'è la regola pura di come un
// delta trasforma l'insieme indicizzato — idempotente per id, senza ricostruire
// tutto. Il Data layer applica lo stesso delta all'indice SwiftData; questo tipo
// ne è l'oracolo logico testabile.

/// Delta della libreria fra due stati: cosa è stato aggiunto, rimosso, modificato.
public struct IndexDelta: Equatable, Sendable {
    /// Asset nuovi da inserire.
    public let added: [LibraryAsset]
    /// Id degli asset da rimuovere.
    public let removed: [String]
    /// Asset esistenti i cui metadati sono cambiati (aggiornati in place per id).
    public let changed: [LibraryAsset]

    public init(added: [LibraryAsset] = [], removed: [String] = [], changed: [LibraryAsset] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }
}

/// Applicazione pura di un delta a uno snapshot in memoria dell'indice.
public enum IncrementalIndex {
    /// Applica `delta` a `snapshot` e restituisce il nuovo insieme, ordinato per id
    /// (deterministico).
    ///
    /// Invarianti:
    ///  • idempotente per id: reinserire un id già presente aggiorna in place,
    ///    non duplica;
    ///  • `removed` vince prima di `added`/`changed` sullo stesso id, poi
    ///    l'eventuale aggiunta lo reintroduce (ordine: remove → upsert);
    ///  • nessuna ricostruzione totale: si toccano solo gli id nel delta.
    public static func apply(_ delta: IndexDelta, to snapshot: [LibraryAsset]) -> [LibraryAsset] {
        // Dizionario per id: upsert O(1), nessun duplicato possibile.
        var byId: [String: LibraryAsset] = [:]
        byId.reserveCapacity(snapshot.count + delta.added.count)
        for asset in snapshot { byId[asset.id] = asset }

        for id in delta.removed { byId.removeValue(forKey: id) }
        for asset in delta.added { byId[asset.id] = asset }
        for asset in delta.changed { byId[asset.id] = asset }

        return byId.values.sorted { $0.id < $1.id }
    }
}
