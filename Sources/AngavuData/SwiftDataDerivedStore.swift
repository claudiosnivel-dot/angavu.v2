import AngavuDomain
import Foundation

// FSE-E2 (Data) — Store SwiftData dei derivati (leva 5).
//
// Persiste i derivati fra gli avvii (feature print, hash, nitidezza, residenza) così
// una ri-scansione ricalcola SOLO il nuovo/cambiato. `DerivedRecord` è il modello, con
// `id` univoco → l'upsert non può duplicare. Come `SwiftDataAssetIndex` (T-012): un
// `ModelContext` dedicato per operazione (mai il contesto main-actor per scritture di
// massa — lezione del freeze on-device), un solo fetch + mappa per id + un solo save.
//
// Solo on-device, zero rete/telemetria: i derivati non escono dal device. SwiftData è
// Apple-only: tutto guardato da `canImport(SwiftData)`; su Linux compila a vuoto.

#if canImport(SwiftData)
import SwiftData

/// Record persistito di un derivato. `id` univoco (un derivato per asset); la
/// `contentVersion` accompagna i valori così la lettura ricostruisce la `DerivedKey`
/// completa e la policy di validità (FSE-E1) può scartare gli stantìi.
@available(macOS 14, iOS 17, *)
@Model
public final class DerivedRecord {
    @Attribute(.unique) public var id: String
    public var contentVersion: String
    public var digest: String?
    public var sharpness: Double?
    public var featurePrint: Data?
    public var residentBytes: Int64?

    public init(
        id: String,
        contentVersion: String,
        digest: String? = nil,
        sharpness: Double? = nil,
        featurePrint: Data? = nil,
        residentBytes: Int64? = nil
    ) {
        self.id = id
        self.contentVersion = contentVersion
        self.digest = digest
        self.sharpness = sharpness
        self.featurePrint = featurePrint
        self.residentBytes = residentBytes
    }
}

@available(macOS 14, iOS 17, *)
extension DerivedRecord {
    convenience init(key: DerivedKey, value: DerivedRecordValue) {
        self.init(
            id: key.id,
            contentVersion: key.contentVersion,
            digest: value.digest,
            sharpness: value.sharpness,
            featurePrint: value.featurePrint,
            residentBytes: value.residentBytes
        )
    }

    /// Aggiorna in place versione + valori (upsert per id): un contenuto cambiato
    /// riscrive la `contentVersion` e i derivati, mai lasciando un valore stantìo.
    func apply(key: DerivedKey, value: DerivedRecordValue) {
        contentVersion = key.contentVersion
        digest = value.digest
        sharpness = value.sharpness
        featurePrint = value.featurePrint
        residentBytes = value.residentBytes
    }

    var value: DerivedRecordValue {
        DerivedRecordValue(
            digest: digest,
            sharpness: sharpness,
            featurePrint: featurePrint,
            residentBytes: residentBytes
        )
    }
}

/// Repository SwiftData dei derivati.
@available(macOS 14, iOS 17, *)
public final class SwiftDataDerivedStore: DerivedResultStoring {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Ogni operazione crea il PROPRIO `ModelContext` dal container (off-main): la
    /// scrittura di massa non tocca il contesto principale (main-actor), evitando la
    /// contesa sulla coda main che bloccò l'app dopo il 100% (stesso motivo di T-012).
    private func makeContext() -> ModelContext { ModelContext(container) }

    public func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws {
        guard !entries.isEmpty else { return }
        let context = makeContext()

        // UN SOLO fetch dei record esistenti, indicizzati per id: O(1) query + O(N) in
        // memoria + un solo save (mai una query per derivato).
        let existing = try context.fetch(FetchDescriptor<DerivedRecord>())
        var byId = [String: DerivedRecord](minimumCapacity: existing.count)
        for record in existing { byId[record.id] = record }

        for (key, value) in entries {
            if let record = byId[key.id] {
                record.apply(key: key, value: value)
            } else {
                let record = DerivedRecord(key: key, value: value)
                context.insert(record)
                byId[key.id] = record
            }
        }
        try context.save()
    }

    public func loadAll() throws -> [DerivedKey: DerivedRecordValue] {
        let context = makeContext()
        let records = try context.fetch(FetchDescriptor<DerivedRecord>())
        var result = [DerivedKey: DerivedRecordValue](minimumCapacity: records.count)
        for record in records {
            result[DerivedKey(id: record.id, contentVersion: record.contentVersion)] = record.value
        }
        return result
    }

    public func remove(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let context = makeContext()
        for targetId in ids {
            var descriptor = FetchDescriptor<DerivedRecord>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1
            if let record = try context.fetch(descriptor).first {
                context.delete(record)
            }
        }
        try context.save()
    }

    public func removeAll() throws {
        let context = makeContext()
        for record in try context.fetch(FetchDescriptor<DerivedRecord>()) {
            context.delete(record)
        }
        try context.save()
    }
}
#endif
