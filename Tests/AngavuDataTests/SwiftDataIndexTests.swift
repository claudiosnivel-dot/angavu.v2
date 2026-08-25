import XCTest

// T-012 — AC-012-1 / AC-012-2. Indice SwiftData: upsert idempotente e query per tipo.
// SwiftData è Apple-only: qui l'oracolo gira al confine Apple (`swift test` su
// macOS 14+/iOS 17+). Su Linux il test degrada onestamente a skip (mai un verde finto).

#if canImport(SwiftData)
import SwiftData
import AngavuDomain
@testable import AngavuData

private func asset(_ id: String, kind: MediaKind) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: kind,
        pixelSize: PixelSize(width: 100, height: 100),
        creationDate: nil,
        subtypes: []
    )
}

@available(macOS 14, iOS 17, *)
final class SwiftDataIndexTests: XCTestCase {

    private func makeIndex() throws -> SwiftDataAssetIndex {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AssetRecord.self, configurations: configuration)
        return SwiftDataAssetIndex(container: container)
    }

    // AC-012-1: upsert dei 2 asset due volte → esattamente 2 record (idempotente).
    func test_upsertIsIdempotentById() throws {
        let index = try makeIndex()
        let assets = [asset("A", kind: .photo), asset("B", kind: .video)]

        try index.upsert(assets)
        try index.upsert(assets) // seconda volta: nessun duplicato

        XCTAssertEqual(try index.count(), 2)
    }

    // Dedup ENTRO lo stesso batch: due asset con lo stesso id in un'unica upsert
    // → un solo record, senza violare il vincolo `.unique` su `id`. L'upsert batch
    // (un fetch solo, mappa per id) deve collassarli come farebbe l'idempotenza fra
    // chiamate separate.
    func test_upsertDeduplicatesWithinASingleBatch() throws {
        let index = try makeIndex()

        try index.upsert([
            asset("A", kind: .photo),
            asset("A", kind: .photo), // stesso id nello stesso batch
            asset("B", kind: .video)
        ])

        XCTAssertEqual(try index.count(), 2)
    }

    // Molti asset in un'unica upsert → esattamente quel numero di record (nessuna
    // perdita né duplicazione col percorso batch a fetch singolo).
    func test_upsertLargeBatchIndexesAll() throws {
        let index = try makeIndex()
        let many = (0..<2000).map { asset("id-\($0)", kind: .photo) }

        try index.upsert(many)

        XCTAssertEqual(try index.count(), 2000)
    }

    // AC-012-2: query per soli video → solo i record di tipo video.
    func test_queryByKindReturnsOnlyVideos() throws {
        let index = try makeIndex()
        try index.upsert([
            asset("photo1", kind: .photo),
            asset("photo2", kind: .photo),
            asset("video1", kind: .video)
        ])

        let videos = try index.assets(matching: AssetQuery(kind: .video))

        XCTAssertEqual(videos.map(\.id), ["video1"])
        XCTAssertTrue(videos.allSatisfy { $0.kind == .video })
    }
}

#else

final class SwiftDataIndexTests: XCTestCase {
    func test_swiftDataUnavailable_skipped() throws {
        throw XCTSkip("SwiftData non disponibile qui; T-012 verificato al confine Apple (macOS/iOS).")
    }
}

#endif
