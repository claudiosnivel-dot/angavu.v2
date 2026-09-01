import XCTest

// FSE-K1 — Oracolo dello store SwiftData dei RISULTATI per categoria (AC-FSE-K1-1,
// parte persistenza). SwiftData è Apple-only: gira al confine Apple (`swift test` su
// macOS 14+/iOS 17+); su Linux degrada onestamente a skip (mai un verde finto).

#if canImport(SwiftData)
import SwiftData
import AngavuDomain
@testable import AngavuData

@available(macOS 14, iOS 17, *)
final class CategoryResultStoreTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: CategoryResultRecord.self, configurations: configuration)
    }

    private func record(
        _ kind: String, keep: [String], removable: [String], at seconds: TimeInterval = 1_000
    ) -> CategoryResultRecordValue {
        CategoryResultRecordValue(
            kind: kind, keepIds: keep, removableIds: removable,
            libraryToken: nil, computedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    // AC-FSE-K1-1 — risultati scritti in una sessione e riletti dopo il «riavvio»
    // (nuovo store dallo stesso container) sono recuperati IDENTICI, keep/removable
    // compresi e nell'ordine stabile.
    func test_persistsAndReloadsIdentically() throws {
        let container = try makeContainer()
        let writer = SwiftDataCategoryResultStore(container: container)

        let duplicates = record("exactDuplicates", keep: ["D1"], removable: ["D2", "D3"])
        let similar = CategoryResultRecordValue(
            kind: "similarPhotos", keepIds: ["S1"], removableIds: ["S2"],
            libraryToken: Data([9, 9]), computedAt: Date(timeIntervalSince1970: 2_000)
        )
        try writer.upsert(duplicates)
        try writer.upsert(similar)

        // «Riavvio»: un nuovo store dallo STESSO container (lo store condiviso persiste).
        let reader = SwiftDataCategoryResultStore(container: container)
        let loaded = try reader.loadAll()

        XCTAssertEqual(loaded, [duplicates, similar], "riletti identici, ordinati per kind")
    }

    // Upsert per kind: un secondo upsert dello stesso kind RIMPIAZZA (mai due record).
    func test_upsertSameKind_replacesNotDuplicates() throws {
        let container = try makeContainer()
        let store = SwiftDataCategoryResultStore(container: container)

        try store.upsert(record("blurryPhotos", keep: [], removable: ["B1", "B2"]))
        try store.upsert(record("blurryPhotos", keep: [], removable: ["B2"], at: 3_000))

        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 1, "un solo record per kind")
        XCTAssertEqual(loaded.first?.removableIds, ["B2"], "il nuovo valore rimpiazza per intero")
        XCTAssertEqual(loaded.first?.computedAt, Date(timeIntervalSince1970: 3_000))
    }

    // Lo store scrive con un contesto DEDICATO (non quello di un osservatore): un
    // contesto separato non ha modifiche pendenti, eppure vede i dati salvati.
    func test_writesUseDedicatedContext() throws {
        let container = try makeContainer()
        let store = SwiftDataCategoryResultStore(container: container)
        let observer = ModelContext(container)

        try store.upsert(record("screenshots", keep: [], removable: ["S1"]))

        XCTAssertFalse(observer.hasChanges, "lo store non deve toccare il contesto osservatore (usa il suo)")
        XCTAssertEqual(try observer.fetchCount(FetchDescriptor<CategoryResultRecord>()), 1,
                       "il save dello store è visibile agli altri contesti dello stesso container")
    }

    // Rimozione per kind (assente → no-op) e svuotamento totale.
    func test_removeKindAndRemoveAll() throws {
        let container = try makeContainer()
        let store = SwiftDataCategoryResultStore(container: container)
        try store.upsert(record("a", keep: [], removable: ["1"]))
        try store.upsert(record("b", keep: [], removable: ["2"]))

        try store.remove(kind: "a")
        XCTAssertEqual(try store.loadAll().map(\.kind), ["b"], "a rimosso, b resta")

        try store.remove(kind: "missing")
        XCTAssertEqual(try store.loadAll().map(\.kind), ["b"], "kind assente: no-op")

        try store.removeAll()
        XCTAssertTrue(try store.loadAll().isEmpty, "removeAll svuota lo store")
    }
}
#endif
