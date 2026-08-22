import XCTest
@testable import AngavuDomain

// T-032 — AC-032-1 / AC-032-2. Selezione keep-one deterministica per cluster.
// Domain puro. Nessuna eliminazione: la proposta è solo dati per safety_net.

final class KeepOneSelectionTests: XCTestCase {

    private func sized(_ id: String, bytes: Int64 = 100) -> SizedAsset {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        return SizedAsset(asset: asset, size: .exact(bytes: bytes))
    }

    private func cluster(ids: [String]) -> ExactDuplicateCluster {
        ExactDuplicateCluster(
            digest: AssetDigest("H"),
            byteSize: 100,
            assets: ids.map { sized($0) }
        )
    }

    // AC-032-1: cluster di 3 duplicati esatti → esattamente 1 keep e 2 removable,
    // e keep + removable coprono l'intero cluster senza sovrapposizioni.
    func test_oneKeepTwoRemovable() throws {
        let proposal = try XCTUnwrap(KeepOneSelection.propose(for: cluster(ids: ["c", "a", "b"])))

        XCTAssertEqual(proposal.removable.count, 2, "esattamente 2 rimovibili")

        // Copertura completa e disgiunta: keep ∪ removable == cluster, keep ∉ removable.
        let keepId = proposal.keep.asset.id
        let removableIds = Set(proposal.removable.map(\.asset.id))
        XCTAssertFalse(removableIds.contains(keepId), "il keep non è tra i removable")
        XCTAssertEqual(
            removableIds.union([keepId]),
            ["a", "b", "c"],
            "keep + removable coprono tutto il cluster"
        )
    }

    // AC-032-2: lo stesso cluster valutato due volte → stesso keep (deterministico),
    // indipendentemente dall'ordine d'ingresso degli asset.
    func test_keepIsDeterministicAcrossEvaluationsAndOrderings() {
        let first = KeepOneSelection.propose(for: cluster(ids: ["c", "a", "b"]))
        let second = KeepOneSelection.propose(for: cluster(ids: ["c", "a", "b"]))
        XCTAssertEqual(first?.keep, second?.keep)

        // Anche con ordine d'ingresso diverso, il keep non cambia.
        let shuffled = KeepOneSelection.propose(for: cluster(ids: ["b", "c", "a"]))
        XCTAssertEqual(first?.keep, shuffled?.keep)
    }

    // Cluster degenere senza asset → nil (nessun force-unwrap, nessun crash).
    func test_emptyClusterYieldsNil() {
        let empty = ExactDuplicateCluster(digest: AssetDigest("H"), byteSize: 0, assets: [])
        XCTAssertNil(KeepOneSelection.propose(for: empty))
    }

    // La comodità batch produce una proposta per ogni cluster valido.
    func test_batchProducesOneProposalPerCluster() {
        let clusters = [cluster(ids: ["a", "b"]), cluster(ids: ["c", "d", "e"])]
        let proposals = KeepOneSelection.proposals(for: clusters)

        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(proposals.map { $0.removable.count }, [1, 2])
    }
}
