import Foundation

// T-012 — Port del repository dell'indice, definito nel Domain (architettura
// esagonale): il Domain dichiara COME interroga/scrive l'indice; l'adapter
// SwiftData del Data layer vi si conforma. Così il Domain resta puro e l'indice
// SwiftData (Apple-only) sta interamente nel Data.

/// Filtro d'interrogazione dell'indice. Campi opzionali: `nil` = nessun vincolo
/// su quel campo.
public struct AssetQuery: Equatable, Sendable {
    /// Filtra per tipo di media.
    public var kind: MediaKind?
    /// Solo asset con dimensione >= questa soglia (byte).
    public var minBytes: Int64?
    /// Solo asset creati prima di questa data (più vecchi di…).
    public var olderThan: Date?

    public init(kind: MediaKind? = nil, minBytes: Int64? = nil, olderThan: Date? = nil) {
        self.kind = kind
        self.minBytes = minBytes
        self.olderThan = olderThan
    }

    /// Query vuota: tutti gli asset.
    public static let all = AssetQuery()
}

/// Lettura dell'indice. Le implementazioni sono on-device; nessun dato esce dal
/// device (zero backend, 00-INDEX §3).
public protocol AssetIndexReading {
    /// Asset che soddisfano il filtro.
    func assets(matching query: AssetQuery) throws -> [LibraryAsset]
    /// Numero totale di asset indicizzati.
    func count() throws -> Int
}

/// Scrittura dell'indice: upsert idempotente per id e rimozione per id.
public protocol AssetIndexWriting {
    /// Inserisce o aggiorna gli asset per id (idempotente: nessun duplicato).
    func upsert(_ assets: [LibraryAsset]) throws
    /// Rimuove gli asset con gli id dati (gli id assenti sono ignorati).
    func remove(ids: [String]) throws
}
