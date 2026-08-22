import XCTest
@testable import AngavuDomain

// T-031 — AC-031-1 / AC-031-2. Cluster per SHA-256 identico, hashing cancellabile.
// Il clustering è Domain puro; l'hashing reale (PhotoKit/CryptoKit) è dietro il
// port `AssetContentHashing` e qui sostituito da un fake. Gira senza device.

/// Fake hasher: mappa l'`id` dell'asset a un digest scelto dal test e registra
/// l'ordine delle chiamate (per provare che i residui NON vengono hashati).
private final class FakeContentHasher: AssetContentHashing {
    /// id asset → valore di digest; un id assente restituisce `nil` (non hashabile).
    private let digests: [String: String]
    private(set) var hashedIds: [String] = []

    init(_ digests: [String: String]) {
        self.digests = digests
    }

    func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        hashedIds.append(asset.id)
        guard let value = digests[asset.id] else { return nil }
        return AssetDigest(value)
    }
}

final class ExactDuplicateClusterTests: XCTestCase {

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

    // AC-031-1: un gruppo candidato con due asset dai byte identici e uno diverso
    // → i due identici finiscono nello stesso cluster, il terzo resta escluso.
    func test_identicalBytesClusterTogetherThirdExcluded() {
        let group = SizeCandidateGroup(
            byteSize: 100,
            assets: [sized("a"), sized("b"), sized("c")]
        )
        // "a" e "b" hanno lo stesso digest; "c" è diverso.
        let hasher = FakeContentHasher(["a": "H1", "b": "H1", "c": "H2"])

        let outcome = ExactDuplicateClustering.clusters(
            from: [group],
            hasher: hasher,
            chunkSize: 8,
            cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        // Un solo cluster (a,b): c non ha compagni con lo stesso digest.
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.digest, AssetDigest("H1"))
        XCTAssertEqual(clusters.first?.byteSize, 100)
        XCTAssertEqual(Set(clusters.first?.assets.map(\.asset.id) ?? []), ["a", "b"])
        XCTAssertFalse(clusters.first?.assets.contains { $0.asset.id == "c" } ?? true)
    }

    // Byte uguali (stessa dimensione) ma contenuto diverso → nessun cluster:
    // la dimensione candida, ma è lo SHA-256 a confermare (o smentire).
    func test_sameSizeDifferentHashesYieldNoCluster() {
        let group = SizeCandidateGroup(byteSize: 100, assets: [sized("a"), sized("b")])
        let hasher = FakeContentHasher(["a": "H1", "b": "H2"])

        let outcome = ExactDuplicateClustering.clusters(
            from: [group], hasher: hasher, chunkSize: 8, cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        XCTAssertTrue(clusters.isEmpty)
    }

    // AC-031-2: cancellazione dopo il primo blocco → esito cancelled, i candidati
    // residui NON vengono hashati (il fake registra solo il primo blocco).
    func test_cancelAfterFirstChunkLeavesResidualsUnhashed() {
        // Quattro candidati identici, un elemento per blocco.
        let group = SizeCandidateGroup(
            byteSize: 100,
            assets: [sized("a"), sized("b"), sized("c"), sized("d")]
        )
        let hasher = FakeContentHasher(["a": "H", "b": "H", "c": "H", "d": "H"])
        let token = CancellationToken()

        let outcome = ExactDuplicateClustering.clusters(
            from: [group],
            hasher: hasher,
            chunkSize: 1,
            cancellation: token
        ) { progress in
            // Dopo il primo blocco hashato, richiedi la cancellazione.
            if progress.processed == 1 { token.cancel() }
        }

        guard case .cancelled(let at) = outcome else {
            return XCTFail("atteso .cancelled, ottenuto \(outcome)")
        }
        XCTAssertEqual(at.processed, 1)
        XCTAssertEqual(at.total, 4)
        XCTAssertFalse(at.isComplete)
        // Prova che i residui non sono stati hashati: una sola chiamata al port.
        XCTAssertEqual(hasher.hashedIds, ["a"])
    }

    // Un asset non hashabile (digest nil, es. originale in iCloud) è escluso dai
    // cluster: mai dichiarato duplicato senza verifica dei byte.
    func test_unhashableAssetIsExcluded() {
        let group = SizeCandidateGroup(
            byteSize: 100,
            assets: [sized("a"), sized("b"), sized("c")]
        )
        // c non ha digest (non verificabile).
        let hasher = FakeContentHasher(["a": "H", "b": "H"])

        let outcome = ExactDuplicateClustering.clusters(
            from: [group], hasher: hasher, chunkSize: 8, cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters.first?.assets.map(\.asset.id) ?? []), ["a", "b"])
    }

    // Cluster ordinati in modo deterministico (dimensione, poi digest) su più gruppi.
    func test_clustersAreDeterministicallyOrdered() {
        let small = SizeCandidateGroup(
            byteSize: 100, assets: [sized("a", bytes: 100), sized("b", bytes: 100)]
        )
        let large = SizeCandidateGroup(
            byteSize: 500, assets: [sized("c", bytes: 500), sized("d", bytes: 500)]
        )
        let hasher = FakeContentHasher(["a": "HB", "b": "HB", "c": "HA", "d": "HA"])

        let outcome = ExactDuplicateClustering.clusters(
            from: [large, small], hasher: hasher, chunkSize: 8, cancellation: CancellationToken()
        )

        guard case .completed(let clusters) = outcome else {
            return XCTFail("atteso .completed, ottenuto \(outcome)")
        }
        // Ordine per dimensione crescente: prima 100, poi 500.
        XCTAssertEqual(clusters.map(\.byteSize), [100, 500])
    }
}
