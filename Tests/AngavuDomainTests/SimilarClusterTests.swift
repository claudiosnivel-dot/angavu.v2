import XCTest
@testable import AngavuDomain

// T-041 — AC-041-1 / AC-041-2 / AC-041-3. Clustering per soglia con fallback dHash,
// a blocchi cancellabili. Il clustering è Domain puro; il feature print reale
// (Vision) è dietro il port e qui sostituito da un fake. Gira senza device.

/// Fake feature-printer che REGISTRA le coppie interrogate (per provare che i
/// residui non vengono processati su cancellazione). Un id in `noFeaturePrint` non
/// ha feature print → distanza `nil` (forza il fallback dHash). Una coppia non
/// elencata ma con feature print restituisce "lontano" (mai simile per via semantica).
private final class RecordingFeaturePrinter: FeaturePrinting {
    private let distances: [Set<String>: Float]
    private let noFeaturePrint: Set<String>
    private(set) var queriedPairs: [Set<String>] = []

    init(distances: [Set<String>: Float], noFeaturePrint: Set<String> = []) {
        self.distances = distances
        self.noFeaturePrint = noFeaturePrint
    }

    func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float? {
        queriedPairs.append([lhs.id, rhs.id])
        if noFeaturePrint.contains(lhs.id) || noFeaturePrint.contains(rhs.id) {
            return nil
        }
        return distances[[lhs.id, rhs.id]] ?? Float.greatestFiniteMagnitude
    }
}

final class SimilarClusterTests: XCTestCase {

    private func candidate(_ id: String, dHash: UInt64? = nil) -> SimilarityCandidate {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        return SimilarityCandidate(asset: asset, dHash: dHash)
    }

    private func ids(_ cluster: SimilarCluster) -> Set<String> {
        Set(cluster.members.map(\.asset.id))
    }

    // AC-041-1: gli asset entro soglia semantica finiscono nello stesso cluster,
    // quelli oltre soglia in cluster distinti.
    func test_withinThresholdClusterTogetherBeyondSeparate() {
        let printer = RecordingFeaturePrinter(distances: [
            ["a", "b"]: 0.1,   // simili (entro 0.3)
            ["a", "c"]: 0.9,   // lontani
            ["b", "c"]: 0.9
        ])
        let thresholds = SimilarityThresholds(semantic: 0.3, hamming: 5)

        let outcome = SimilarClustering.clusters(
            of: [candidate("a"), candidate("b"), candidate("c")],
            provider: printer,
            thresholds: thresholds,
            chunkSize: 8,
            cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(ids(clusters[0]), ["a", "b"])
        XCTAssertEqual(ids(clusters[1]), ["c"])
    }

    // AC-041-2: un asset privo di feature print ma con dHash disponibile viene
    // raggruppato usando la distanza di Hamming del dHash (fallback attivo).
    func test_missingFeaturePrintFallsBackToDHash() {
        // "b" non ha feature print → la coppia {a,b} degrada al dHash; i due dHash
        // differiscono di 1 bit soltanto (entro la soglia di Hamming = 5).
        let printer = RecordingFeaturePrinter(distances: [:], noFeaturePrint: ["b"])
        let thresholds = SimilarityThresholds(semantic: 0.3, hamming: 5)

        let outcome = SimilarClustering.clusters(
            of: [candidate("a", dHash: 0b0000), candidate("b", dHash: 0b0001)],
            provider: printer,
            thresholds: thresholds,
            chunkSize: 8,
            cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        // Un solo cluster: il fallback dHash li ha raggruppati nonostante il feature
        // print mancante per "b".
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(ids(clusters[0]), ["a", "b"])
    }

    // Nessun feature print E nessun dHash per un asset → mai raggruppato (nessun
    // falso "via libera" su un asset non verificabile).
    func test_neitherFeaturePrintNorDHashIsNeverGrouped() {
        let printer = RecordingFeaturePrinter(distances: [:], noFeaturePrint: ["a", "b"])
        let thresholds = SimilarityThresholds(semantic: 0.3, hamming: 5)

        let outcome = SimilarClustering.clusters(
            of: [candidate("a", dHash: nil), candidate("b", dHash: nil)],
            provider: printer,
            thresholds: thresholds,
            chunkSize: 8,
            cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        // Due cluster distinti da un solo membro: non c'era modo di verificarne la similarità.
        XCTAssertEqual(clusters.count, 2)
    }

    // AC-041-3: cancellazione dopo il primo blocco → esito cancelled, i candidati
    // residui NON vengono processati (il provider è interrogato solo entro il primo blocco).
    func test_cancelAfterFirstChunkLeavesResidualsUnprocessed() {
        let printer = RecordingFeaturePrinter(distances: [
            ["a", "b"]: 0.1   // a,b simili: b viene confrontato con a nel primo blocco
        ])
        let thresholds = SimilarityThresholds(semantic: 0.3, hamming: 5)
        let token = CancellationToken()

        let outcome = SimilarClustering.clusters(
            of: [candidate("a"), candidate("b"), candidate("c"), candidate("d")],
            provider: printer,
            thresholds: thresholds,
            chunkSize: 2,
            cancellation: token
        ) { progress in
            // Dopo il primo blocco (2 processati), richiedi la cancellazione.
            if progress.processed == 2 { token.cancel() }
        }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
        XCTAssertEqual(at.processed, 2)
        XCTAssertEqual(at.total, 4)
        XCTAssertFalse(at.isComplete)
        // Prova che c e d non sono stati processati: l'unica coppia interrogata è {a,b}.
        XCTAssertEqual(printer.queriedPairs, [["a", "b"]])
    }
}
