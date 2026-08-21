import XCTest
@testable import AngavuDomain

// T-020 — AC-020-1 / AC-020-2. Aggregazione byte per categoria, exact vs estimated.

final class DashboardAggregateTests: XCTestCase {

    private func photo(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 100, height: 100),
                     creationDate: nil, subtypes: [])
    }

    private func video(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .video, pixelSize: PixelSize(width: 100, height: 100),
                     creationDate: nil, subtypes: [])
    }

    private func screenshot(_ id: String) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 100, height: 100),
                     creationDate: nil, subtypes: [.screenshot])
    }

    // AC-020-1: asset di byte noti in due categorie → ogni categoria riporta la
    // somma corretta dei byte dei suoi asset.
    func test_sumsBytesPerCategory() {
        let items = [
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 1_000)),
            SizedAsset(asset: photo("p2"), size: .exact(bytes: 2_000)),
            SizedAsset(asset: video("v1"), size: .exact(bytes: 10_000))
        ]

        let aggregate = DashboardAggregator.aggregate(items)

        let photos = aggregate.bytes(for: .photo)
        XCTAssertEqual(photos?.count, 2)
        XCTAssertEqual(photos?.exactBytes, 3_000)
        XCTAssertEqual(photos?.totalBytes, 3_000)

        let videos = aggregate.bytes(for: .video)
        XCTAssertEqual(videos?.count, 1)
        XCTAssertEqual(videos?.exactBytes, 10_000)

        // Categoria senza asset non compare.
        XCTAssertNil(aggregate.bytes(for: .screenshot))
    }

    // Le categorie sono disgiunte: uno screenshot non è conteggiato anche fra le
    // foto (niente doppio conteggio nelle somme).
    func test_screenshotIsDisjointFromPhoto() {
        let items = [
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 1_000)),
            SizedAsset(asset: screenshot("s1"), size: .exact(bytes: 500))
        ]

        let aggregate = DashboardAggregator.aggregate(items)

        XCTAssertEqual(aggregate.bytes(for: .photo)?.count, 1)
        XCTAssertEqual(aggregate.bytes(for: .photo)?.exactBytes, 1_000)
        XCTAssertEqual(aggregate.bytes(for: .screenshot)?.count, 1)
        XCTAssertEqual(aggregate.bytes(for: .screenshot)?.exactBytes, 500)
    }

    // AC-020-2: mix di exact ed estimated → la quota estimated è riportata
    // separatamente da quella exact, mai fusa in un unico numero "esatto".
    func test_estimatedKeptSeparateFromExact() {
        let items = [
            SizedAsset(asset: photo("p1"), size: .exact(bytes: 1_000)),
            SizedAsset(asset: photo("p2"), size: .estimated(bytes: 4_000))
        ]

        let aggregate = DashboardAggregator.aggregate(items)
        let photos = aggregate.bytes(for: .photo)

        XCTAssertEqual(photos?.exactBytes, 1_000, "solo i byte exact nella quota exact")
        XCTAssertEqual(photos?.estimatedBytes, 4_000, "i byte estimated restano nella loro quota")
        XCTAssertTrue(photos?.hasEstimatedPortion == true, "il totale non è interamente esatto")
        // Il totale esiste ma NON è un numero "esatto": la porzione stimata è marcata.
        XCTAssertEqual(photos?.totalBytes, 5_000)
    }

    // Aggregato vuoto: nessuna categoria.
    func test_emptyInput() {
        let aggregate = DashboardAggregator.aggregate([])
        XCTAssertTrue(aggregate.categories.isEmpty)
    }
}
