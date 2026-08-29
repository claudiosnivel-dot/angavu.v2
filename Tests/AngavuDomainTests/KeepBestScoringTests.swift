import XCTest
@testable import AngavuDomain

// T-042 — AC-042-1 / AC-042-2. Punteggio qualità e regola best-of-cluster. Lo
// scoring reale (Core Image/Vision) è dietro il port e qui sostituito da un fake.

/// Fake scorer: mappa l'`id` dell'asset a un `QualityScore` scelto dal test.
private struct FakeQualityScorer: QualityScoring {
    let scores: [String: QualityScore]

    func score(for asset: LibraryAsset) throws -> QualityScore {
        scores[asset.id] ?? QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
    }
}

private struct ScorerFailure: Error {}

/// Fake scorer che LANCIA per gli id indicati (simula un fallimento Vision/decodifica
/// on-device), altrimenti restituisce lo score dato.
private struct PartiallyFailingScorer: QualityScoring {
    let scores: [String: QualityScore]
    let failingIds: Set<String>

    func score(for asset: LibraryAsset) throws -> QualityScore {
        if failingIds.contains(asset.id) { throw ScorerFailure() }
        return scores[asset.id] ?? QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
    }
}

final class KeepBestScoringTests: XCTestCase {

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

    // AC-042-1: in un cluster di 3 con punteggi noti, il ranking mette al primo posto
    // (keep) l'asset col punteggio più alto; gli altri restano removable.
    func test_bestOfClusterIsHighestScore() throws {
        let cluster = SimilarCluster(members: [candidate("a"), candidate("b"), candidate("c")])
        let scorer = FakeQualityScorer(scores: [
            "a": QualityScore(sharpness: 0.2, faceQuality: 0.1, aesthetics: 0.1),   // overall 0.4
            "b": QualityScore(sharpness: 0.9, faceQuality: 0.5, aesthetics: 0.3),   // overall 1.7 (migliore)
            "c": QualityScore(sharpness: 0.5, faceQuality: nil, aesthetics: nil)    // overall 0.5
        ])

        let ranked = try ClusterQualityRanking.ranked(cluster, scoring: scorer)

        XCTAssertEqual(ranked.map(\.candidate.asset.id), ["b", "c", "a"])
        // Keep = il migliore; removable = gli altri.
        XCTAssertEqual(ranked.first?.candidate.asset.id, "b")
        XCTAssertEqual(Set(ranked.dropFirst().map(\.candidate.asset.id)), ["a", "c"])
    }

    // A parità di punteggio, l'ordine è stabile per id crescente (deterministico).
    func test_tiesBreakByIdAscending() throws {
        let cluster = SimilarCluster(members: [candidate("z"), candidate("m"), candidate("a")])
        let sameScore = QualityScore(sharpness: 0.5, faceQuality: nil, aesthetics: nil)
        let scorer = FakeQualityScorer(scores: ["z": sameScore, "m": sameScore, "a": sameScore])

        let ranked = try ClusterQualityRanking.ranked(cluster, scoring: scorer)

        XCTAssertEqual(ranked.map(\.candidate.asset.id), ["a", "m", "z"])
    }

    // AC-042-2: senza aesthetics score (iOS 17), il punteggio usa nitidezza/volti
    // senza quel termine e non fallisce.
    func test_scoreWithoutAestheticsUsesAvailableTerms() {
        let withoutAesthetics = QualityScore(sharpness: 0.6, faceQuality: 0.3, aesthetics: nil)
        // overall = 0.6 + 0.3, il termine aesthetics assente non concorre né fa fallire.
        XCTAssertEqual(withoutAesthetics.overall, 0.9, accuracy: 1e-9)

        let noFaces = QualityScore(sharpness: 0.4, faceQuality: nil, aesthetics: nil)
        XCTAssertEqual(noFaces.overall, 0.4, accuracy: 1e-9)
    }

    // RESILIENZA (fix crash device «foto simili» non cachate): se il quality scorer LANCIA
    // per UN membro, la categoria NON deve fallire. Il ranking degrada quel membro a score
    // neutro (overall 0 → ultimo) e restituisce comunque TUTTI i membri, così la scansione
    // unificata cacha «foto simili» invece di lasciarla non-cachata (ricalcolo al tap).
    func test_ranking_survivesPerMemberScoringFailure() throws {
        let cluster = SimilarCluster(members: [candidate("a"), candidate("b"), candidate("c")])
        let scorer = PartiallyFailingScorer(
            scores: [
                "a": QualityScore(sharpness: 0.9, faceQuality: 0.5, aesthetics: 0.3), // overall 1.7 (migliore)
                "c": QualityScore(sharpness: 0.5, faceQuality: nil, aesthetics: nil)  // overall 0.5
            ],
            failingIds: ["b"] // "b" lancia → degradato a neutro (overall 0)
        )

        // NON deve lanciare: la categoria sopravvive al fallimento del singolo membro.
        let ranked = try ClusterQualityRanking.ranked(cluster, scoring: scorer)

        // Tutti i membri presenti; il membro non scorabile ("b") è ultimo (neutro).
        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(ranked.map(\.candidate.asset.id), ["a", "c", "b"])
        XCTAssertEqual(ranked.first?.candidate.asset.id, "a", "il keep resta il migliore realmente scorato")
    }
}
