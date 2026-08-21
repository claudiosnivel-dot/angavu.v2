import XCTest
import AngavuDomain
@testable import AngavuData

// T-051 — AC-051-1 / AC-051-2. Coordinamento eliminazione batch + indice.
// Il coordinator è Swift puro (nessun tipo PhotoKit/SwiftData): l'oracolo gira
// ovunque con fake. L'adapter reale `SystemAssetDeleter` è verificato al confine
// Apple tramite lo stesso protocollo.

/// Fake deleter: registra la chiamata e restituisce un esito configurato.
private final class FakeAssetDeleter: AssetDeleting {
    let result: BatchDeletionResult
    private(set) var receivedIds: [[String]] = []

    init(result: BatchDeletionResult) {
        self.result = result
    }

    func delete(ids: [String]) async -> BatchDeletionResult {
        receivedIds.append(ids)
        return result
    }
}

/// Fake index writer in memoria: parte popolato e traccia le rimozioni.
private final class FakeIndexWriter: AssetIndexWriting {
    private(set) var ids: Set<String>

    init(seed: [String]) {
        self.ids = Set(seed)
    }

    func upsert(_ assets: [LibraryAsset]) throws {
        for asset in assets { ids.insert(asset.id) }
    }

    func remove(ids removed: [String]) throws {
        for id in removed { ids.remove(id) }
    }
}

final class AssetDeletionTests: XCTestCase {

    // AC-051-1: batch confermato di 3, deleter riporta success → deleter invocato
    // UNA sola volta con i 3 asset e l'indice li rimuove tutti.
    func test_successRemovesBatchFromIndexWithSingleCall() async throws {
        let batch = ["A", "B", "C"]
        let deleter = FakeAssetDeleter(result: .success)
        let index = FakeIndexWriter(seed: batch + ["D"]) // D non nel batch
        let coordinator = BatchDeletionCoordinator(deleter: deleter, index: index)

        let result = try await coordinator.delete(ids: batch)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(deleter.receivedIds.count, 1, "un solo alert/chiamata per batch")
        XCTAssertEqual(deleter.receivedIds.first, batch)
        XCTAssertEqual(index.ids, ["D"], "i 3 asset del batch rimossi, D intatto")
    }

    // AC-051-2: deleter riporta cancellazione dell'alert → nessun record rimosso.
    func test_cancelledRemovesNothing() async throws {
        let batch = ["A", "B", "C"]
        let deleter = FakeAssetDeleter(result: .cancelled)
        let index = FakeIndexWriter(seed: batch)
        let coordinator = BatchDeletionCoordinator(deleter: deleter, index: index)

        let result = try await coordinator.delete(ids: batch)

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(deleter.receivedIds.count, 1)
        XCTAssertEqual(index.ids, Set(batch), "annullamento dell'alert: indice invariato")
    }

    // Un esito failed lascia anch'esso l'indice invariato (coerenza con il device).
    func test_failedRemovesNothing() async throws {
        let batch = ["A", "B"]
        let deleter = FakeAssetDeleter(result: .failed(reason: "boom"))
        let index = FakeIndexWriter(seed: batch)
        let coordinator = BatchDeletionCoordinator(deleter: deleter, index: index)

        let result = try await coordinator.delete(ids: batch)

        XCTAssertEqual(result, .failed(reason: "boom"))
        XCTAssertEqual(index.ids, Set(batch), "su failed l'indice non cambia")
    }
}
