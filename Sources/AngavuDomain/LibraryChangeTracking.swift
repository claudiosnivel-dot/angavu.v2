import Foundation

// FSE-K2 (Domain) — Port del tracciamento PERSISTENTE dei cambi di libreria.
//
// Origine (diagnosi 2026-09-01, bug RICORRENTE «le categorie pesanti riscansionano
// all'ingresso»): i risultati per categoria ora sopravvivono al relaunch (FSE-K1), ma
// per SERVIRLI onestamente bisogna sapere COSA è cambiato nella libreria dall'ultima
// scansione — senza riscansionare. Fondamento Apple (letto): `PHPersistentChangeToken`
// + `fetchPersistentChanges(since:)` (iOS 16+) — token serializzabile persistito fra i
// lanci, delta `inserted/updated/deleted` per id, rescan completo SOLO quando il token
// è scaduto (WWDC22 «Discover PhotoKit change history»).
//
// Il port è nel Domain (esagonale); il token è OPACO (`Data`, NSSecureCoding
// serializzato dall'adapter) e locale, zero rete. La `modificationDate` NON è mai usata
// come prova di validità (inaffidabile, DTS): il delta per id è l'unica fonte.

/// Delta persistente della libreria fra un token salvato e il presente: id inseriti,
/// aggiornati, eliminati. Un `localIdentifier` può comparire sia in `deleted` sia in
/// `inserted` (id cambiato, iOS 16+): è delete+insert, mai un match per nome.
public struct LibraryChangeDelta: Equatable, Sendable {
    public let inserted: Set<String>
    public let updated: Set<String>
    public let deleted: Set<String>

    public init(inserted: Set<String> = [], updated: Set<String> = [], deleted: Set<String> = []) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
    }

    /// Nessun id toccato in nessuna direzione.
    public var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && deleted.isEmpty }

    /// Unione di tutti gli id toccati (in qualunque direzione).
    public var touchedIds: Set<String> { inserted.union(updated).union(deleted) }
}

/// Esito di una richiesta di cambi «da un token»: un delta, oppure il token è
/// SCADUTO (la storia persistente non copre più quel punto → serve una scansione
/// completa), oppure i dettagli NON sono disponibili (nessuna prova → mai un delta
/// vuoto fabbricato).
public enum LibraryChangeOutcome: Equatable, Sendable {
    case delta(LibraryChangeDelta)
    case expired
    case unavailable
}

/// Port del tracciamento persistente dei cambi. L'adapter reale (PhotoKit) vive nel
/// Data layer; i test usano una spia.
public protocol LibraryChangeTracking {
    /// Token opaco dello stato CORRENTE della libreria; `nil` = non disponibile.
    func currentToken() -> Data?

    /// Cambi avvenuti dal token dato a oggi.
    func changes(since token: Data) -> LibraryChangeOutcome
}

/// Null-object: nessun token e nessun delta — riporta `.unavailable`, mai un delta
/// vuoto fabbricato (che farebbe servire risultati stantìi come freschi). Con questo
/// tracker la policy di validità dichiara sempre `.fullRescan`: onesto per difetto.
public struct NoLibraryChangeTracker: LibraryChangeTracking {
    public init() {}
    public func currentToken() -> Data? { nil }
    public func changes(since token: Data) -> LibraryChangeOutcome { .unavailable }
}
