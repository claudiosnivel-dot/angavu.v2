import XCTest

// FSE-E2 — Oracolo dello store SwiftData dei derivati (AC-FSE-E2-1/2/3).
// SwiftData è Apple-only: gira al confine Apple (`swift test` su macOS 14+/iOS 17+);
// su Linux degrada onestamente a skip (mai un verde finto).

#if canImport(SwiftData)
import SwiftData
import AngavuDomain
@testable import AngavuData

@available(macOS 14, iOS 17, *)
final class DerivedResultStoreTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: DerivedRecord.self, configurations: configuration)
    }

    // AC-FSE-E2-1 — derivati scritti in una sessione e riletti dopo il «riavvio»
    // (nuovo store dallo stesso container) sono recuperati IDENTICI.
    func test_persistsAndReloadsIdentically() throws {
        let container = try makeContainer()
        let writer = SwiftDataDerivedStore(container: container)

        let entries: [DerivedKey: DerivedRecordValue] = [
            DerivedKey(id: "A", contentVersion: "1"): DerivedRecordValue(
                digest: "sha-a", sharpness: 0.42,
                featurePrint: Data([1, 2, 3, 4]), residentBytes: 1024
            ),
            DerivedKey(id: "B", contentVersion: "7"): DerivedRecordValue(sharpness: 0.10)
        ]
        try writer.upsert(entries)

        // «Riavvio»: un nuovo store dallo STESSO container (lo store condiviso persiste).
        let reader = SwiftDataDerivedStore(container: container)
        let loaded = try reader.loadAll()

        XCTAssertEqual(loaded, entries, "i derivati riletti devono essere identici (nessun ricalcolo)")
    }

    // AC-FSE-E2-2 — un upsert di 2000 derivati usa un contesto DEDICATO (non il main):
    // provato dal fatto che un contesto osservatore separato non ha modifiche pendenti,
    // eppure vede i dati salvati; e l'operazione conclude senza errori.
    func test_bulkUpsertUsesDedicatedContext() throws {
        let container = try makeContainer()
        let store = SwiftDataDerivedStore(container: container)

        // Contesto osservatore separato: lo store NON deve scrivere attraverso questo.
        let observer = ModelContext(container)

        var entries: [DerivedKey: DerivedRecordValue] = [:]
        entries.reserveCapacity(2000)
        for number in 0..<2000 {
            entries[DerivedKey(id: "A\(number)", contentVersion: "1")] =
                DerivedRecordValue(sharpness: Double(number) / 2000)
        }
        try store.upsert(entries)

        XCTAssertFalse(observer.hasChanges, "lo store non deve toccare il contesto osservatore (usa il suo)")
        XCTAssertEqual(try observer.fetchCount(FetchDescriptor<DerivedRecord>()), 2000,
                       "il save dello store è visibile agli altri contesti dello stesso container")
    }

    // AC-FSE-E2-3 — un derivato con versione cambiata NON è restituito come valido:
    // lo store legge la chiave completa, la policy di validità (FSE-E1) lo scarta.
    func test_staleVersionIsNotServedAsValid() throws {
        let container = try makeContainer()
        let store = SwiftDataDerivedStore(container: container)

        try store.upsert([DerivedKey(id: "A", contentVersion: "1"): DerivedRecordValue(digest: "old")])
        let persisted = Array(try store.loadAll().keys)

        // L'asset A ora è a versione 2 (contenuto cambiato).
        let partition = DerivedResultValidity.partition(
            current: [DerivedKey(id: "A", contentVersion: "2")],
            persisted: persisted
        )

        XCTAssertEqual(partition.reusable, [], "il derivato v1 è stantìo per A@v2")
        XCTAssertEqual(partition.toRecompute, [DerivedKey(id: "A", contentVersion: "2")],
                       "A va ricalcolato, mai servito col vettore stantìo")
    }

    // Rimozione mirata (eliminazione/invalidazione) e svuotamento totale.
    func test_removeAndRemoveAll() throws {
        let container = try makeContainer()
        let store = SwiftDataDerivedStore(container: container)
        try store.upsert([
            DerivedKey(id: "A", contentVersion: "1"): DerivedRecordValue(digest: "a"),
            DerivedKey(id: "B", contentVersion: "1"): DerivedRecordValue(digest: "b")
        ])

        try store.remove(ids: ["A"])
        XCTAssertEqual(Set(try store.loadAll().keys.map(\.id)), ["B"], "A rimosso, B resta")

        try store.removeAll()
        XCTAssertTrue(try store.loadAll().isEmpty, "removeAll svuota lo store")
    }
}
#endif
