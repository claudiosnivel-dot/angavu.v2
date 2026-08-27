import Foundation

// FSE-E2 (Domain) — Port dello store dei derivati + valore persistibile.
//
// Il port è nel Domain (esagonale, come `AssetIndexReading/Writing`); l'adapter reale
// SwiftData vive nel Data layer. Il Domain vede SOLO valori puri (`DerivedRecordValue`):
// il feature print è `Data` OPACO (bytes serializzati), mai un tipo di Vision — così
// l'altitudine resta intatta (00-INDEX §1bis) e la logica di validità (FSE-E1) è
// testabile senza device.
//
// La chiave di persistenza è l'`id` dell'asset (un derivato per asset); la
// `contentVersion` viaggia col valore così la lettura ricostruisce la `DerivedKey`
// completa e la policy `DerivedResultValidity` (FSE-E1) può scartare gli stantìi.

/// Valori derivati persistibili di un asset. Ogni campo è OPZIONALE: un derivato non
/// ancora calcolato (o non calcolabile on-device) resta `nil`, mai un valore fabbricato.
public struct DerivedRecordValue: Equatable, Sendable {
    /// Digest del contenuto (SHA-256 esadecimale) per i duplicati esatti.
    public var digest: String?
    /// Nitidezza normalizzata 0…1 (foto sfocate).
    public var sharpness: Double?
    /// Feature print semantico serializzato (bytes OPACHI: nessun tipo di Vision qui).
    public var featurePrint: Data?
    /// Byte residenti sul device per l'asset (residenza).
    public var residentBytes: Int64?

    public init(
        digest: String? = nil,
        sharpness: Double? = nil,
        featurePrint: Data? = nil,
        residentBytes: Int64? = nil
    ) {
        self.digest = digest
        self.sharpness = sharpness
        self.featurePrint = featurePrint
        self.residentBytes = residentBytes
    }
}

/// Port di persistenza dei derivati: legge tutto in memoria all'avvio scan, scrive in
/// upsert per id, invalida per id o del tutto. L'implementazione reale (SwiftData) usa
/// un `ModelContext` dedicato per operazione (off-main), come l'indice (T-012).
public protocol DerivedResultStoring {
    /// Tutti i derivati persistiti, indicizzati per chiave completa (`id` +
    /// `contentVersion`): serve a ripopolare la cache in memoria a inizio scansione.
    func loadAll() throws -> [DerivedKey: DerivedRecordValue]

    /// Upsert per `id`: aggiorna il record esistente (nuova `contentVersion` + valori)
    /// o ne inserisce uno nuovo. Idempotente per id.
    func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws

    /// Rimuove i derivati per gli id dati (eliminazione confermata / invalidazione
    /// mirata dall'observer di libreria).
    func remove(ids: [String]) throws

    /// Svuota lo store (invalidazione totale, es. cambio libreria completo).
    func removeAll() throws
}

/// Null-object: nessun derivato persistito, ogni scrittura è un no-op. Coerente con gli
/// altri null-object (`EmptyAssetHandleResolver`…): finché `live()` non cabla lo store
/// reale, la scansione ricalcola sempre — mai un derivato finto servito da uno store assente.
public struct NoDerivedResultStore: DerivedResultStoring {
    public init() {}
    public func loadAll() throws -> [DerivedKey: DerivedRecordValue] { [:] }
    public func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws {}
    public func remove(ids: [String]) throws {}
    public func removeAll() throws {}
}
