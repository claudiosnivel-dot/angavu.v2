import Foundation

// FSE-K1 (Domain) — Port dello store dei RISULTATI per categoria + valore persistibile.
//
// Origine (diagnosi 2026-09-01, bug RICORRENTE «le categorie pesanti riscansionano
// all'ingresso»): i risultati composti delle categorie vivevano SOLO in memoria e il
// ripristino al lancio salta la scansione che li popola → dopo ogni cold relaunch lo
// store era vuoto e ogni categoria rigirava il rilevatore. FSE-J6 ha persistito i
// DERIVATI per-asset (digest…), non i RISULTATI composti: questo port chiude quel buco.
//
// Il port è nel Domain (esagonale, come `DerivedResultStoring`); l'adapter reale
// SwiftData vive nel Data layer. Si persistono SOLO id (keep/removable) e metadati
// di validità — mai immagini, mai byte di contenuto — così l'altitudine resta intatta
// e la logica è testabile senza device.
//
// `libraryToken` è lo slot per il change token di libreria (FSE-K2,
// `PHPersistentChangeToken` serializzato, OPACO): in K1 è sempre `nil`; la policy di
// validità che lo consuma è K2. `computedAt` alimenta il badge di freschezza (D-1)
// anche dopo un relaunch.

/// Risultato composto di una categoria, persistibile: solo id e metadati.
public struct CategoryResultRecordValue: Equatable, Sendable {
    /// Identificatore della categoria (es. `CleanupCategory.rawValue`); chiave univoca.
    public let kind: String
    /// Id da tenere (mai eliminabili), nell'ordine stabile della review.
    public let keepIds: [String]
    /// Id eliminabili, nell'ordine stabile della review.
    public let removableIds: [String]
    /// Change token di libreria al momento del calcolo (FSE-K2), opaco. `nil` = ignoto.
    public let libraryToken: Data?
    /// Istante del calcolo (badge di freschezza D-1).
    public let computedAt: Date

    public init(
        kind: String,
        keepIds: [String],
        removableIds: [String],
        libraryToken: Data? = nil,
        computedAt: Date
    ) {
        self.kind = kind
        self.keepIds = keepIds
        self.removableIds = removableIds
        self.libraryToken = libraryToken
        self.computedAt = computedAt
    }
}

/// Port di persistenza dei risultati per categoria: un record per `kind`, upsert
/// idempotente, rimozione per kind o totale. L'implementazione reale (SwiftData) usa
/// un `ModelContext` dedicato per operazione (off-main), come indice e derivati.
public protocol CategoryResultStoring {
    /// Tutti i record persistiti (uno per kind), in ordine stabile per kind.
    func loadAll() throws -> [CategoryResultRecordValue]

    /// Upsert per `kind`: aggiorna il record esistente o ne inserisce uno nuovo.
    /// Idempotente: mai due record per lo stesso kind.
    func upsert(_ value: CategoryResultRecordValue) throws

    /// Rimuove il record del kind dato (assente → no-op).
    func remove(kind: String) throws

    /// Svuota lo store (invalidazione totale).
    func removeAll() throws
}

/// Null-object: nessun risultato persistito, ogni scrittura è un no-op. Coerente con
/// gli altri null-object (`NoDerivedResultStore`…): finché il grafo reale non cabla lo
/// store SwiftData, nulla sopravvive al relaunch — mai un risultato finto servito da uno
/// store assente.
public struct NoCategoryResultStore: CategoryResultStoring {
    public init() {}
    public func loadAll() throws -> [CategoryResultRecordValue] { [] }
    public func upsert(_ value: CategoryResultRecordValue) throws {}
    public func remove(kind: String) throws {}
    public func removeAll() throws {}
}
