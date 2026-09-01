import AngavuDomain
import Foundation

// FSE-K1 (Data) — Store SwiftData dei RISULTATI per categoria.
//
// Persiste fra i lanci gli id keep/removable composti dalla scansione (mai immagini,
// mai byte di contenuto), così il ripristino al lancio può IDRATARE la cache in
// memoria invece di lasciarla vuota (bug ricorrente «le categorie pesanti
// riscansionano all'ingresso»). `CategoryResultRecord` ha `kind` univoco → l'upsert
// non può duplicare. Come `SwiftDataAssetIndex` (T-012) e `SwiftDataDerivedStore`
// (FSE-E2): un `ModelContext` DEDICATO per operazione (mai il contesto main-actor),
// un fetch mirato + un solo save.
//
// Solo on-device, zero rete/telemetria. SwiftData è Apple-only: tutto guardato da
// `canImport(SwiftData)`; su Linux compila a vuoto.

#if canImport(SwiftData)
import SwiftData

/// Record persistito del risultato di una categoria. `kind` univoco (un record per
/// categoria); `libraryToken` è lo slot opaco per il change token (FSE-K2).
@available(macOS 14, iOS 17, *)
@Model
public final class CategoryResultRecord {
    @Attribute(.unique) public var kind: String
    public var keepIds: [String]
    public var removableIds: [String]
    public var libraryToken: Data?
    public var computedAt: Date

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

@available(macOS 14, iOS 17, *)
extension CategoryResultRecord {
    convenience init(value: CategoryResultRecordValue) {
        self.init(
            kind: value.kind,
            keepIds: value.keepIds,
            removableIds: value.removableIds,
            libraryToken: value.libraryToken,
            computedAt: value.computedAt
        )
    }

    /// Aggiorna in place (upsert per kind): il nuovo risultato rimpiazza il precedente
    /// per intero, mai un id stantìo lasciato indietro.
    func apply(_ value: CategoryResultRecordValue) {
        keepIds = value.keepIds
        removableIds = value.removableIds
        libraryToken = value.libraryToken
        computedAt = value.computedAt
    }

    var value: CategoryResultRecordValue {
        CategoryResultRecordValue(
            kind: kind,
            keepIds: keepIds,
            removableIds: removableIds,
            libraryToken: libraryToken,
            computedAt: computedAt
        )
    }
}

/// Repository SwiftData dei risultati per categoria.
@available(macOS 14, iOS 17, *)
public final class SwiftDataCategoryResultStore: CategoryResultStoring {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Ogni operazione crea il PROPRIO `ModelContext` dal container (off-main): la
    /// scrittura non tocca il contesto principale (main-actor) — stessa lezione del
    /// freeze on-device di T-012.
    private func makeContext() -> ModelContext { ModelContext(container) }

    public func loadAll() throws -> [CategoryResultRecordValue] {
        let context = makeContext()
        let descriptor = FetchDescriptor<CategoryResultRecord>(sortBy: [SortDescriptor(\.kind)])
        return try context.fetch(descriptor).map(\.value)
    }

    public func upsert(_ value: CategoryResultRecordValue) throws {
        let context = makeContext()
        if let record = try fetchRecord(kind: value.kind, in: context) {
            record.apply(value)
        } else {
            context.insert(CategoryResultRecord(value: value))
        }
        try context.save()
    }

    public func remove(kind: String) throws {
        let context = makeContext()
        guard let record = try fetchRecord(kind: kind, in: context) else { return }
        context.delete(record)
        try context.save()
    }

    public func removeAll() throws {
        let context = makeContext()
        for record in try context.fetch(FetchDescriptor<CategoryResultRecord>()) {
            context.delete(record)
        }
        try context.save()
    }

    private func fetchRecord(kind targetKind: String, in context: ModelContext) throws -> CategoryResultRecord? {
        var descriptor = FetchDescriptor<CategoryResultRecord>(
            predicate: #Predicate { $0.kind == targetKind }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
#endif
