import XCTest
@testable import AngavuDomain

// T-011 — AC-011-1 / AC-011-2. Mapping puro da item grezzi a LibraryAsset.

private struct FakeEnumerator {
    let items: [RawEnumeratedAsset]
}

private func raw(
    _ id: String,
    media: Int,
    date: Date? = nil,
    screenshot: Bool = false,
    live: Bool = false
) -> RawEnumeratedAsset {
    RawEnumeratedAsset(
        localIdentifier: id,
        mediaTypeRawValue: media,
        pixelWidth: 100,
        pixelHeight: 100,
        creationDate: date,
        isScreenshot: screenshot,
        isLivePhoto: live
    )
}

final class LibraryAssetMappingTests: XCTestCase {

    // AC-011-1: 3 asset noti → 3 LibraryAsset con id/tipo/data corrispondenti.
    func test_mapsKnownAssets_preservingIdKindDate() {
        let d0 = Date(timeIntervalSince1970: 1_000)
        let d1 = Date(timeIntervalSince1970: 2_000)
        let fake = FakeEnumerator(items: [
            raw("A", media: 1, date: d0),            // foto
            raw("B", media: 2, date: d1),            // video
            raw("C", media: 1, date: nil, screenshot: true) // foto screenshot
        ])

        let mapped = fake.items.compactMap(LibraryAssetMapper.map)

        XCTAssertEqual(mapped.count, 3)
        XCTAssertEqual(mapped.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(mapped.map(\.kind), [.photo, .video, .photo])
        XCTAssertEqual(mapped[0].creationDate, d0)
        XCTAssertEqual(mapped[1].creationDate, d1)
        XCTAssertNil(mapped[2].creationDate)
        XCTAssertTrue(mapped[2].subtypes.contains(.screenshot))
    }

    // Tipi non gestiti (es. audio, raw value 3) vengono scartati.
    func test_dropsUnhandledMediaTypes() {
        XCTAssertNil(LibraryAssetMapper.map(raw("X", media: 3)))
        XCTAssertNil(LibraryAssetMapper.map(raw("Y", media: 0)))
    }

    // AC-011-2: cancellazione dopo il primo blocco → esito cancelled e i blocchi
    // successivi non vengono mappati.
    func test_batchMapping_cancelsAfterFirstChunk() {
        let items = (0..<10).map { raw("id\($0)", media: 1) }
        let token = CancellationToken()

        let outcome = LibraryAssetMapper.mapBatch(
            items,
            chunkSize: 3,
            cancellation: token
        ) { progress in
            // Cancella non appena il primo blocco è stato processato.
            if progress.processed >= 3 { token.cancel() }
        }

        switch outcome {
        case .cancelled(let at):
            // Processati solo i primi blocchi, non tutti i 10.
            XCTAssertGreaterThanOrEqual(at.processed, 3)
            XCTAssertLessThan(at.processed, 10)
        default:
            XCTFail("atteso esito cancelled, ottenuto \(outcome)")
        }
    }

    // Batch AMPIO: mappa tutti gli item preservando ordine e conteggio. Blocca la
    // correttezza dell'accumulatore a riferimento (fix O(N²)→O(N)) a scala; con la
    // vecchia piega per valore questo sarebbe lentissimo (copia dell'intero array a
    // ogni elemento), ma la correttezza deve restare identica.
    func test_batchMapping_largeBatchPreservesOrderAndCount() {
        let total = 10_000
        let items = (0..<total).map { raw("id\($0)", media: $0 % 2 == 0 ? 1 : 2) }

        let outcome = LibraryAssetMapper.mapBatch(items, chunkSize: 256, cancellation: CancellationToken())

        guard case .completed(let assets) = outcome else {
            return XCTFail("atteso completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(assets.count, total)
        XCTAssertEqual(assets.first?.id, "id0")
        XCTAssertEqual(assets.last?.id, "id\(total - 1)")
        XCTAssertEqual(assets[1].kind, .video)   // dispari → video
        XCTAssertEqual(assets[2].kind, .photo)   // pari → foto
    }

    // Il batch completo (senza cancellazione) mappa tutti gli item gestiti.
    func test_batchMapping_completesAll() {
        let items = (0..<5).map { raw("id\($0)", media: 2) }
        let outcome = LibraryAssetMapper.mapBatch(items, chunkSize: 2, cancellation: CancellationToken())

        guard case .completed(let assets) = outcome else {
            return XCTFail("atteso completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(assets.count, 5)
        XCTAssertEqual(assets.map(\.kind), Array(repeating: MediaKind.video, count: 5))
    }
}
