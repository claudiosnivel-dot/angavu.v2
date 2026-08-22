import XCTest
@testable import AngavuDomain

// T-030 — AC-030-1 / AC-030-2. Raggruppamento candidati per dimensione byte.
// Domain puro: l'oracolo gira senza device.

final class SizeCandidateGroupingTests: XCTestCase {

    /// Asset foto con la dimensione byte data (exact): l'`id` è unico per byte
    /// dell'indice così i gruppi restano distinguibili nei test.
    private func sized(_ id: String, bytes: Int64) -> SizedAsset {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        return SizedAsset(asset: asset, size: .exact(bytes: bytes))
    }

    // AC-030-1: dimensioni [100, 100, 200, 300, 300, 300] → gruppi 100 (x2) e
    // 300 (x3); il 200 singolo è escluso (niente hashing da fare su di esso).
    func test_groupsSizesWithMoreThanOneAsset() {
        let items = [
            sized("a", bytes: 100),
            sized("b", bytes: 100),
            sized("c", bytes: 200),
            sized("d", bytes: 300),
            sized("e", bytes: 300),
            sized("f", bytes: 300)
        ]

        let groups = SizeCandidateGrouping.candidateGroups(items)

        // Due soli gruppi candidati, ordinati per dimensione crescente.
        XCTAssertEqual(groups.map(\.byteSize), [100, 300])

        let group100 = groups.first { $0.byteSize == 100 }
        XCTAssertEqual(group100?.assets.count, 2)
        XCTAssertEqual(group100?.assets.map(\.asset.id), ["a", "b"])

        let group300 = groups.first { $0.byteSize == 300 }
        XCTAssertEqual(group300?.assets.count, 3)
        XCTAssertEqual(group300?.assets.map(\.asset.id), ["d", "e", "f"])

        // Il singolo (200) non è un candidato.
        XCTAssertNil(groups.first { $0.byteSize == 200 })
    }

    // AC-030-2: asset tutti di dimensione distinta → nessun candidato (l'insieme
    // dei gruppi è vuoto, nessun hashing da fare).
    func test_allDistinctSizesYieldNoCandidates() {
        let items = [
            sized("a", bytes: 100),
            sized("b", bytes: 200),
            sized("c", bytes: 300)
        ]

        let groups = SizeCandidateGrouping.candidateGroups(items)

        XCTAssertTrue(groups.isEmpty)
    }

    // Insieme vuoto: nessun candidato, nessun crash.
    func test_emptyInputYieldsNoCandidates() {
        XCTAssertTrue(SizeCandidateGrouping.candidateGroups([]).isEmpty)
    }

    // La marcatura exact/estimated non separa i candidati: la dimensione è solo
    // un filtro; la verità la stabilisce l'hashing (T-031).
    func test_exactAndEstimatedSameSizeGroupTogether() {
        let exact = sized("a", bytes: 100)
        let estimatedAsset = LibraryAsset(
            id: "b", kind: .photo, pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil, subtypes: []
        )
        let estimated = SizedAsset(asset: estimatedAsset, size: .estimated(bytes: 100))

        let groups = SizeCandidateGrouping.candidateGroups([exact, estimated])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.assets.count, 2)
    }
}
