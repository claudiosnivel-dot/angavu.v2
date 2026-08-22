import XCTest
@testable import AngavuDomain

// T-043 — AC-043-1 / AC-043-2. Proposta di eliminazione per cluster di simili:
// keep il migliore, removable il resto. Solo dati per safety_net; nessuna eliminazione.

/// Fake scorer: mappa l'`id` a un `QualityScore` scelto dal test.
private struct FakeQualityScorer: QualityScoring {
    let scores: [String: QualityScore]

    func score(for asset: LibraryAsset) throws -> QualityScore {
        scores[asset.id] ?? QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
    }
}

final class SimilarDeletionProposalTests: XCTestCase {

    private func candidate(_ id: String) -> SimilarityCandidate {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        return SimilarityCandidate(asset: asset, dHash: nil)
    }

    private func score(_ overall: Double) -> QualityScore {
        QualityScore(sharpness: overall, faceQuality: nil, aesthetics: nil)
    }

    // AC-043-1: un cluster con un best individuato e 2 removable → keep è il best,
    // removable contiene esattamente i 2 restanti.
    func test_proposalKeepsBestAndMarksRestRemovable() throws {
        let cluster = SimilarCluster(members: [candidate("a"), candidate("b"), candidate("c")])
        let scorer = FakeQualityScorer(scores: [
            "a": score(0.2),
            "b": score(0.9),   // migliore
            "c": score(0.5)
        ])

        let proposal = try SimilarDeletionProposal.compose(for: cluster, scoring: scorer)

        XCTAssertNotNil(proposal)
        XCTAssertEqual(proposal?.keep.asset.id, "b")
        XCTAssertEqual(Set(proposal?.removable.map(\.asset.id) ?? []), ["a", "c"])
        XCTAssertEqual(proposal?.removable.count, 2)
    }

    // AC-043-2: un cluster con un solo asset → removable vuoto (nulla da proporre).
    func test_singletonClusterHasNoRemovable() throws {
        let cluster = SimilarCluster(members: [candidate("solo")])
        let scorer = FakeQualityScorer(scores: ["solo": score(0.7)])

        let proposal = try SimilarDeletionProposal.compose(for: cluster, scoring: scorer)

        XCTAssertNotNil(proposal)
        XCTAssertEqual(proposal?.keep.asset.id, "solo")
        XCTAssertTrue(proposal?.removable.isEmpty ?? false)
    }

    // Un cluster vuoto non produce proposta (nessun keep possibile).
    func test_emptyClusterYieldsNoProposal() throws {
        let cluster = SimilarCluster(members: [])
        let scorer = FakeQualityScorer(scores: [:])

        let proposal = try SimilarDeletionProposal.compose(for: cluster, scoring: scorer)

        XCTAssertNil(proposal)
    }

    // Comodità: proposte per più cluster in un colpo solo.
    func test_proposalsForMultipleClusters() throws {
        let clusters = [
            SimilarCluster(members: [candidate("a"), candidate("b")]),
            SimilarCluster(members: [candidate("solo")])
        ]
        let scorer = FakeQualityScorer(scores: [
            "a": score(0.9), "b": score(0.1), "solo": score(0.5)
        ])

        let proposals = try SimilarDeletionProposal.proposals(for: clusters, scoring: scorer)

        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(proposals[0].keep.asset.id, "a")
        XCTAssertEqual(proposals[0].removable.map(\.asset.id), ["b"])
        XCTAssertTrue(proposals[1].removable.isEmpty)
    }
}
