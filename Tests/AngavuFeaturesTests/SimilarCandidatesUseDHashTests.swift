import XCTest
import AngavuDomain

// FSE-H2 — AC-FSE-H2-1. La composizione dei candidati alla review dei simili porta il
// dHash REALE dietro il port `AssetPerceptualHashing`: un candidato ha il dHash quando il
// port lo produce, altrimenti `nil` — MAI un valore fabbricato. Provato con un provider
// fake, su CI (il calcolo reale del dHash dalla miniatura è device-only, AC-FSE-H2-3, §7).

/// Provider fake: dHash per id da una mappa; assente → `nil`.
private struct FakeDHasher: AssetPerceptualHashing {
    let dHashById: [String: UInt64]
    func dHash(for asset: LibraryAsset) -> UInt64? { dHashById[asset.id] }
}

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

private func completedValue<Result>(_ outcome: AnalysisOutcome<Result>) -> Result? {
    if case .completed(let value) = outcome { return value }
    return nil
}

final class SimilarCandidatesUseDHashTests: XCTestCase {

    // AC-FSE-H2-1: ogni candidato porta il dHash quando disponibile, `nil` altrimenti,
    // nell'ordine d'input. Nessun valore fabbricato per l'asset senza dHash.
    func test_candidates_carryRealDHash_orNilNeverFabricated() {
        let assets = [photo("A"), photo("B"), photo("C")]
        let hasher = FakeDHasher(dHashById: ["A": 0x00, "C": 0xFF])

        guard let candidates = completedValue(
            SimilarCandidateComposition.candidates(for: assets, hashing: hasher)
        ) else {
            return XCTFail("composizione non completata")
        }

        XCTAssertEqual(candidates.map(\.asset.id), ["A", "B", "C"], "ordine d'input preservato")
        XCTAssertEqual(candidates[0].dHash, 0x00, "A porta il dHash reale")
        XCTAssertNil(candidates[1].dHash, "B senza dHash resta nil, mai fabbricato")
        XCTAssertEqual(candidates[2].dHash, 0xFF, "C porta il dHash reale")
    }

    // Input vuoto ⇒ nessun candidato, completato (mai un fallimento su lista vuota).
    func test_emptyInput_completesWithNoCandidates() {
        let outcome = SimilarCandidateComposition.candidates(
            for: [], hashing: FakeDHasher(dHashById: [:])
        )
        XCTAssertEqual(completedValue(outcome)?.isEmpty, true)
    }

    // La composizione è cancellabile e riporta progresso monotòno: la fase costosa
    // (una decodifica per foto) non è mai un "0% infinito" né un lavoro non interrompibile.
    func test_reportsProgress_andIsCancellable() {
        let assets = (0..<200).map { photo("P\($0)") }
        let hasher = FakeDHasher(dHashById: [:])

        var progresses: [AnalysisProgress] = []
        _ = SimilarCandidateComposition.candidates(
            for: assets, hashing: hasher,
            analysis: .serial(chunkSize: 32)
        ) { progresses.append($0) }

        XCTAssertEqual(progresses.last?.processed, 200, "a fine corsa tutti processati")
        XCTAssertTrue(zip(progresses, progresses.dropFirst()).allSatisfy { $0.processed <= $1.processed },
                      "progresso monotòno non decrescente")

        // Cancellazione prima dell'avvio → esito cancelled col progresso, mai completed.
        let token = CancellationToken()
        token.cancel()
        let outcome = SimilarCandidateComposition.candidates(
            for: assets, hashing: hasher, cancellation: token
        )
        guard case .cancelled = outcome else {
            return XCTFail("un token già cancellato deve dare .cancelled, mai .completed")
        }
    }
}
