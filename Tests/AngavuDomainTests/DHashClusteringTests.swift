import XCTest
@testable import AngavuDomain

// FSE-H1 — AC-FSE-H1-3 / AC-FSE-H1-4. Clustering delle foto simili per dHash a memoria
// limitata via BK-tree. Aritmetica pura sui 64 bit: gira senza device.

final class DHashClusteringTests: XCTestCase {

    private func candidate(_ id: String, dHash: UInt64?) -> SimilarityCandidate {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 100, height: 100),
            creationDate: nil,
            subtypes: []
        )
        return SimilarityCandidate(asset: asset, dHash: dHash)
    }

    private func ids(_ cluster: SimilarCluster) -> [String] {
        cluster.members.map(\.asset.id)
    }

    /// Clustering di RIFERIMENTO a forza bruta sulla distanza di Hamming: componenti
    /// connesse del grafo "vicini entro soglia", con lo STESSO ordinamento della
    /// produzione (membri per indice, cluster per indice minimo). È l'oracolo di parità.
    private func bruteForceClusters(
        _ candidates: [SimilarityCandidate],
        maxDistance: Int
    ) -> [SimilarCluster] {
        let total = candidates.count
        var parent = Array(0..<total)
        func root(of node: Int) -> Int {
            var current = node
            while parent[current] != current { current = parent[current] }
            return current
        }
        func union(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            parent[max(lhsRoot, rhsRoot)] = min(lhsRoot, rhsRoot)
        }
        for left in 0..<total {
            guard let leftHash = candidates[left].dHash else { continue }
            for right in (left + 1)..<total {
                guard let rightHash = candidates[right].dHash else { continue }
                if SimilarClustering.hammingDistance(leftHash, rightHash) <= maxDistance {
                    union(left, right)
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in 0..<total {
            groups[root(of: index), default: []].append(index)
        }
        return groups
            .sorted { ($0.value.first ?? 0) < ($1.value.first ?? 0) }
            .map { SimilarCluster(members: $0.value.map { candidates[$0] }) }
    }

    // AC-FSE-H1-3: due candidati entro soglia → stesso cluster; uno oltre soglia →
    // cluster distinto; un dHash nil → singleton (mai un falso simile).
    func test_withinThresholdGroupBeyondSeparateNilSingleton() {
        let candidates = [
            candidate("a", dHash: 0x0000_0000_0000_0000),
            candidate("b", dHash: 0x0000_0000_0000_0003),   // Hamming 2 da "a" → simile
            candidate("c", dHash: 0xFFFF_FFFF_FFFF_FFFF),   // lontano → cluster proprio
            candidate("d", dHash: nil)                       // non verificabile → singleton
        ]

        let clusters = SimilarClustering.clustersByHash(of: candidates, maxHammingDistance: 3)

        XCTAssertEqual(clusters.map(ids), [["a", "b"], ["c"], ["d"]])
    }

    // Il dHash nil NON viene mai unito, nemmeno se un altro candidato è nil: due nil
    // restano due singleton distinti (nessun "via libera" fabbricato).
    func test_multipleNilHashesStayDistinctSingletons() {
        let candidates = [
            candidate("a", dHash: nil),
            candidate("b", dHash: nil)
        ]
        let clusters = SimilarClustering.clustersByHash(of: candidates, maxHammingDistance: 10)
        XCTAssertEqual(clusters.map(ids), [["a"], ["b"]])
    }

    // Componenti connesse per transitività: a~b, b~e (catena) → un solo cluster anche
    // se a ed e sono oltre soglia diretta. Parità con la forza bruta lo garantisce.
    func test_transitiveChainFormsSingleCluster() {
        let candidates = [
            candidate("a", dHash: 0x00),
            candidate("b", dHash: 0x01),   // d1 da a
            candidate("e", dHash: 0x03)    // d1 da b, d2 da a
        ]
        let clusters = SimilarClustering.clustersByHash(of: candidates, maxHammingDistance: 1)
        // a-b (d1) e b-e (d1) connessi → catena {a,b,e}; a-e (d2) irrilevante per la connessione.
        XCTAssertEqual(clusters.map(ids), [["a", "b", "e"]])
    }

    // Lista vuota → nessun cluster.
    func test_emptyInputYieldsNoClusters() {
        XCTAssertTrue(SimilarClustering.clustersByHash(of: [], maxHammingDistance: 3).isEmpty)
    }

    // AC-FSE-H1-4: parità con la forza bruta su una batteria di soglie e un dataset con
    // catene, cluster separati e un nil. Il BK-tree accelera, non cambia il risultato.
    func test_parityWithBruteForceAcrossThresholds() {
        let hashes: [UInt64?] = [
            0x0000_0000_0000_0000,
            0x0000_0000_0000_0001,
            0x0000_0000_0000_0003,
            0x0000_0000_0000_000F,
            0x0000_0000_0000_00FF,
            0xFFFF_FFFF_FFFF_FFFF,
            0xFFFF_FFFF_FFFF_FFFE,
            0x8000_0000_0000_0000,
            nil,
            0x0000_0000_0000_0002
        ]
        let candidates = hashes.enumerated().map { candidate("id\($0.offset)", dHash: $0.element) }

        for maxDistance in [0, 1, 2, 3, 5, 8, 16, 64] {
            let produced = SimilarClustering.clustersByHash(of: candidates, maxHammingDistance: maxDistance)
            let reference = bruteForceClusters(candidates, maxDistance: maxDistance)
            XCTAssertEqual(produced, reference, "parità alla soglia di Hamming \(maxDistance)")
        }
    }

    // Soglia negativa trattata come 0: solo hash identici sono uniti.
    func test_negativeThresholdBehavesAsExactMatch() {
        let candidates = [
            candidate("a", dHash: 0x00AB),
            candidate("b", dHash: 0x00AB),   // identico
            candidate("c", dHash: 0x00AC)    // diverso
        ]
        let clusters = SimilarClustering.clustersByHash(of: candidates, maxHammingDistance: -5)
        XCTAssertEqual(clusters.map(ids), [["a", "b"], ["c"]])
    }
}
