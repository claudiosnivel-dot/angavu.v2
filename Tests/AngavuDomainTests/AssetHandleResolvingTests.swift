import XCTest
@testable import AngavuDomain

// FSE-B1 — Oracolo della risoluzione batch dei PHAsset (Domain puro, gira su Linux/CI).
//
// La PERFORMANCE non è oracolabile in CI (L-COL-006): qui si prova solo la LOGICA —
// batch in una sola chiamata, chunking a copertura totale, nessun placeholder finto.
// Il guadagno di velocità è device-only (§7).
//   • AC-FSE-B1-1: risoluzione in UN batch, id inesistente assente (mai crash/placeholder).
//   • AC-FSE-B1-3: chunk deterministici che coprono tutti gli id, senza duplicati né buchi.

// MARK: - Doppioni di test

private final class FakeHandle: AssetHandle {
    let assetLocalIdentifier: String
    init(_ id: String) { self.assetLocalIdentifier = id }
}

/// Closure-spia: registra ogni blocco ricevuto e risolve SOLO gli id noti come
/// esistenti (gli altri sono omessi, come farebbe `PHFetchResult` con un id assente).
private final class ChunkSpy {
    private(set) var chunksReceived: [[String]] = []
    private let existing: Set<String>

    init(existing: Set<String>) { self.existing = existing }

    func resolve(_ chunk: [String]) -> [AssetHandle] {
        chunksReceived.append(chunk)
        return chunk.filter { existing.contains($0) }.map { FakeHandle($0) }
    }

    var callCount: Int { chunksReceived.count }
    var flattenedIDs: [String] { chunksReceived.flatMap { $0 } }
}

final class AssetHandleResolvingTests: XCTestCase {

    // AC-FSE-B1-1 — 5 id di cui 1 inesistente: i 4 esistenti risolti in UNA chiamata
    // di batch; l'inesistente è assente, mai un crash né un placeholder finto.
    func testBatchResolvesExistingInOneCallAndOmitsMissing() {
        let ids = ["A", "B", "C", "D", "MISSING"]
        let spy = ChunkSpy(existing: ["A", "B", "C", "D"])
        let resolver = BatchAssetHandleResolver(chunkSize: 64, resolveChunk: spy.resolve)

        let resolved = resolver.resolve(localIdentifiers: ids)

        // Una sola chiamata di batch, con tutti e 5 gli id insieme (5 ≤ chunk 64).
        XCTAssertEqual(spy.callCount, 1)
        XCTAssertEqual(spy.chunksReceived.first, ids)

        // I 4 esistenti risolti; l'inesistente assente (nil), mai un placeholder.
        XCTAssertEqual(resolved.count, 4)
        XCTAssertEqual(resolved.resolvedIdentifiers, ["A", "B", "C", "D"])
        XCTAssertNotNil(resolved.handle(for: "A"))
        XCTAssertNil(resolved.handle(for: "MISSING"))
    }

    // AC-FSE-B1-1 (guardia) — un id inesistente non fa crashare né inventa un handle.
    func testAllMissingYieldsEmptyMapNoCrash() {
        let spy = ChunkSpy(existing: [])
        let resolver = BatchAssetHandleResolver(chunkSize: 8, resolveChunk: spy.resolve)

        let resolved = resolver.resolve(localIdentifiers: ["X", "Y"])

        XCTAssertEqual(resolved.count, 0)
        XCTAssertNil(resolved.handle(for: "X"))
    }

    // AC-FSE-B1-3 — chunking puro: un batch più grande del chunk è spezzato in blocchi
    // deterministici che coprono ogni id ESATTAMENTE una volta (ordine preservato).
    func testChunkedCoversAllIdentifiersWithoutDuplicatesOrGaps() {
        let ids = (0..<250).map { "id-\($0)" }

        let chunks = AssetIdentifierBatches.chunked(ids, chunkSize: 64)

        // 250 / 64 = 4 blocchi (64, 64, 64, 58).
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks.map(\.count), [64, 64, 64, 58])
        // Nessun blocco eccede il chunk.
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 64 })
        // Concatenazione = elenco originale (copertura totale, ordine, nessun buco).
        XCTAssertEqual(chunks.flatMap { $0 }, ids)
        // Nessun duplicato introdotto.
        XCTAssertEqual(Set(chunks.flatMap { $0 }).count, 250)
    }

    // AC-FSE-B1-3 (via orchestratore) — il resolver spezza in chunk deterministici e
    // copre tutti gli id senza duplicati né buchi, provato dalla closure-spia.
    func testResolverChunksLargeBatchDeterministically() {
        let ids = (0..<130).map { "id-\($0)" }
        let spy = ChunkSpy(existing: Set(ids))
        let resolver = BatchAssetHandleResolver(chunkSize: 50, resolveChunk: spy.resolve)

        let resolved = resolver.resolve(localIdentifiers: ids)

        // 130 / 50 = 3 blocchi (50, 50, 30).
        XCTAssertEqual(spy.callCount, 3)
        XCTAssertEqual(spy.chunksReceived.map(\.count), [50, 50, 30])
        // Ogni id passato una sola volta agli adapter (nessun duplicato né buco).
        XCTAssertEqual(spy.flattenedIDs, ids)
        XCTAssertEqual(resolved.count, 130)
    }

    // Guardia di robustezza: chunkSize non valido è trattato come 1 (nessun blocco
    // vuoto, nessun ciclo infinito), e l'elenco vuoto non produce blocchi.
    func testChunkSizeGuards() {
        XCTAssertEqual(AssetIdentifierBatches.chunked([], chunkSize: 10), [])
        XCTAssertEqual(
            AssetIdentifierBatches.chunked(["a", "b"], chunkSize: 0),
            [["a"], ["b"]]
        )
        XCTAssertEqual(
            AssetIdentifierBatches.chunked(["a", "b"], chunkSize: -5),
            [["a"], ["b"]]
        )
    }

    // Guardia mappa: a parità di id l'ultimo handle vince (deterministico), la mappa
    // non duplica per chiave.
    func testResolvedMapKeepsLastHandlePerIdentifier() {
        let first = FakeHandle("A")
        let second = FakeHandle("A")
        let resolved = ResolvedAssetHandles([first, second])

        XCTAssertEqual(resolved.count, 1)
        XCTAssertTrue(resolved.handle(for: "A") === second)
    }

    // Il null-object non risolve nulla: mai un handle finto (coerente con L-COL-006).
    func testEmptyResolverYieldsNoHandles() {
        let resolved = EmptyAssetHandleResolver().resolve(localIdentifiers: ["A", "B"])
        XCTAssertEqual(resolved.count, 0)
        XCTAssertNil(resolved.handle(for: "A"))
    }
}
