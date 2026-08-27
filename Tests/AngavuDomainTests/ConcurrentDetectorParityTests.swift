import XCTest
@testable import AngavuDomain

// FSE-D2 — Oracolo di PARITÀ: i rilevatori CPU-bound danno lo STESSO risultato col
// motore seriale e col motore concorrente (`PerItemAnalysis`), AC-FSE-D2-1/2.
//
// Il parallelismo è un dettaglio di ESECUZIONE: la fase per-item indipendente
// (nitidezza, hashing, qualità, feature print) gira in parallelo, ma l'output è in
// ordine d'input e la combinazione ordine-dipendente resta seriale → il risultato di
// dominio (cluster, keep, removable, insieme di sfocate) è identico. Con abbastanza
// elementi il motore concorrente spezza in più onde: la parità vale comunque.
//
// I fake dei port sono value-type con dizionari immutabili (`let`): letture concorrenti
// sicure. La correttezza thread degli ADAPTER reali (cache Vision) è device-only (§7).

// MARK: - Fake dei port (immutabili → sicuri in lettura concorrente)

private struct FakeSharpness: SharpnessScoring {
    let sharpnessById: [String: Double]
    func sharpness(for asset: LibraryAsset) throws -> Double? { sharpnessById[asset.id] }
}

private struct FakeHasher: AssetContentHashing {
    let digestsById: [String: String]
    func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        digestsById[asset.id].map(AssetDigest.init)
    }
}

private struct FakeFeaturePrinter: FeaturePrinting {
    let distancesByPair: [Set<String>: Float]
    func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float? {
        distancesByPair[Set([lhs.id, rhs.id])]
    }
}

private struct FakeQuality: QualityScoring {
    let sharpnessById: [String: Double]
    func score(for asset: LibraryAsset) throws -> QualityScore {
        QualityScore(sharpness: sharpnessById[asset.id] ?? 0, faceQuality: nil, aesthetics: nil)
    }
}

// MARK: - Helper

private func photo(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: nil, subtypes: [])
}

private func sized(_ id: String, bytes: Int64) -> SizedAsset {
    SizedAsset(asset: photo(id), size: .exact(bytes: bytes))
}

private let serial = PerItemAnalysis.serial(chunkSize: 8)
private let concurrent = PerItemAnalysis.concurrent(concurrency: 8)

final class ConcurrentDetectorParityTests: XCTestCase {

    // MARK: AC-FSE-D2-2 — Sfocate: parità + cancellazione reattiva

    func test_blurry_concurrentMatchesSerial() {
        // 60 foto con nitidezza alternata (metà sotto soglia, metà sopra).
        let assets = (0..<60).map { photo("P\(String(format: "%03d", $0))") }
        var sharpness: [String: Double] = [:]
        for (index, asset) in assets.enumerated() {
            sharpness[asset.id] = index.isMultiple(of: 2) ? 0.1 : 0.9
        }
        let scoring = FakeSharpness(sharpnessById: sharpness)
        let threshold = BlurThreshold(minimumSharpness: 0.3)

        let serialOutcome = BlurClassification.blurry(
            among: assets, scoring: scoring, threshold: threshold,
            cancellation: CancellationToken(), analysis: serial
        )
        let concurrentOutcome = BlurClassification.blurry(
            among: assets, scoring: scoring, threshold: threshold,
            cancellation: CancellationToken(), analysis: concurrent
        )

        XCTAssertEqual(serialOutcome, concurrentOutcome, "sfocate: concorrente == seriale")
        // Sanity: metà sono sfocate (le pari), in ordine d'input.
        if case .completed(let blurry) = concurrentOutcome {
            XCTAssertEqual(blurry.count, 30)
            XCTAssertEqual(blurry.first?.id, "P000")
        } else {
            XCTFail("atteso completed")
        }
    }

    func test_blurry_concurrentIsCancellable() {
        let assets = (0..<60).map { photo("P\($0)") }
        let scoring = FakeSharpness(sharpnessById: [:])   // tutte non misurabili → nil
        let token = CancellationToken()
        token.cancel()   // cancellato prima di partire

        let outcome = BlurClassification.blurry(
            among: assets, scoring: scoring, threshold: BlurThreshold(minimumSharpness: 0.3),
            cancellation: token, analysis: concurrent
        )

        guard case .cancelled = outcome else {
            return XCTFail("un token cancellato deve dare .cancelled, mai un falso completed")
        }
    }

    // MARK: AC-FSE-D2-1 — Duplicati esatti: parità

    func test_exactDuplicates_concurrentMatchesSerial() {
        // 40 asset: coppie con stessa dimensione+digest → cluster; il resto unico.
        var groups: [SizeCandidateGroup] = []
        var digests: [String: String] = [:]
        for pair in 0..<20 {
            let idA = "D\(pair)a", idB = "D\(pair)b"
            let bytes = Int64(1000 + pair)
            groups.append(SizeCandidateGroup(
                byteSize: bytes,
                assets: [sized(idA, bytes: bytes), sized(idB, bytes: bytes)]
            ))
            digests[idA] = "same\(pair)"
            digests[idB] = "same\(pair)"
        }
        let hasher = FakeHasher(digestsById: digests)

        let serialOutcome = ExactDuplicateClustering.clusters(
            from: groups, hasher: hasher, cancellation: CancellationToken(), analysis: serial
        )
        let concurrentOutcome = ExactDuplicateClustering.clusters(
            from: groups, hasher: hasher, cancellation: CancellationToken(), analysis: concurrent
        )

        XCTAssertEqual(serialOutcome, concurrentOutcome, "duplicati: concorrente == seriale")
        if case .completed(let clusters) = concurrentOutcome {
            XCTAssertEqual(clusters.count, 20, "20 cluster di duplicati")
        } else {
            XCTFail("atteso completed")
        }
    }

    // MARK: AC-FSE-D2-1 — Simili: clustering greedy invariante col motore

    func test_similarClustering_concurrentMatchesSerial() {
        // 30 foto in 15 coppie simili (distanza 0.1) e lontane fra coppie (1.0).
        let candidates = (0..<30).map { SimilarityCandidate(asset: photo("S\($0)"), dHash: nil) }
        var distances: [Set<String>: Float] = [:]
        for outer in 0..<candidates.count {
            for inner in (outer + 1)..<candidates.count {
                let close = (outer / 2 == inner / 2)   // stessa coppia
                distances[Set([candidates[outer].asset.id, candidates[inner].asset.id])] = close ? 0.1 : 1.0
            }
        }
        let provider = FakeFeaturePrinter(distancesByPair: distances)
        let thresholds = SimilarityThresholds(semantic: 0.5, hamming: 10)

        let serialOutcome = SimilarClustering.clusters(
            of: candidates, provider: provider, thresholds: thresholds,
            cancellation: CancellationToken(), analysis: serial
        )
        let concurrentOutcome = SimilarClustering.clusters(
            of: candidates, provider: provider, thresholds: thresholds,
            cancellation: CancellationToken(), analysis: concurrent
        )

        XCTAssertEqual(serialOutcome, concurrentOutcome, "clustering simili: concorrente == seriale")
        if case .completed(let clusters) = concurrentOutcome {
            XCTAssertEqual(clusters.count, 15, "15 cluster di coppie simili")
        } else {
            XCTFail("atteso completed")
        }
    }

    // MARK: AC-FSE-D2-1 — Simili: keep/removable col ranking qualità parallelo

    func test_similarProposals_concurrentQualityMatchesSerial() throws {
        // Cluster di 4 con qualità distinte → keep deterministico, removable il resto.
        let members = (0..<4).map { SimilarityCandidate(asset: photo("Q\($0)"), dHash: nil) }
        let cluster = SimilarCluster(members: members)
        let quality = FakeQuality(sharpnessById: ["Q0": 0.2, "Q1": 0.9, "Q2": 0.5, "Q3": 0.7])

        let serialProposals = try SimilarDeletionProposal.proposals(
            for: [cluster], scoring: quality, analysis: serial
        )
        let concurrentProposals = try SimilarDeletionProposal.proposals(
            for: [cluster], scoring: quality, analysis: concurrent
        )

        XCTAssertEqual(serialProposals, concurrentProposals, "keep/removable: qualità concorrente == seriale")
        XCTAssertEqual(concurrentProposals.first?.keep.asset.id, "Q1", "keep = la più nitida")
    }
}
