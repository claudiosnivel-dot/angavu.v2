import XCTest
@testable import AngavuDomain

// FSE-H1 — AC-FSE-H1-1 / AC-FSE-H1-2. Albero BK sui dHash a 64 bit con distanza di
// Hamming. Aritmetica pura (nessuna dipendenza da Vision/piattaforma): gira senza device.

final class BKTreeTests: XCTestCase {

    /// Ricerca lineare a forza bruta: gli id il cui hash è entro `maxDistance` da `hash`.
    /// È l'ORACOLO di parità del BK-tree (il risultato non deve cambiare, solo il costo).
    private func linearSearch(
        _ entries: [(id: String, hash: UInt64)],
        hash: UInt64,
        maxDistance: Int
    ) -> Set<String> {
        Set(entries
            .filter { SimilarClustering.hammingDistance($0.hash, hash) <= maxDistance }
            .map { $0.id })
    }

    // AC-FSE-H1-1: la query restituisce ESATTAMENTE gli id entro Hamming ≤ d (parità
    // con la ricerca lineare), su una batteria di hash e soglie.
    func test_queryReturnsExactlyIdsWithinDistance() {
        let entries: [(id: String, hash: UInt64)] = [
            ("a", 0x0000_0000_0000_0000),
            ("b", 0x0000_0000_0000_0001),   // Hamming 1 da "a"
            ("c", 0x0000_0000_0000_0003),   // Hamming 2 da "a"
            ("d", 0x0000_0000_0000_000F),   // Hamming 4 da "a"
            ("e", 0xFFFF_FFFF_FFFF_FFFF),   // Hamming 64 da "a"
            ("f", 0xFFFF_FFFF_FFFF_FFFE),   // Hamming 63 da "a"
            ("g", 0x0000_0000_0000_00FF)    // Hamming 8 da "a"
        ]

        var tree = BKTree<String>()
        for entry in entries { tree.insert(entry.id, hash: entry.hash) }
        XCTAssertEqual(tree.count, entries.count)

        // Query e soglie variabili: ogni caso confrontato con la ricerca lineare.
        let probes: [(hash: UInt64, maxDistance: Int)] = [
            (0x0000_0000_0000_0000, 0),
            (0x0000_0000_0000_0000, 1),
            (0x0000_0000_0000_0000, 2),
            (0x0000_0000_0000_0000, 4),
            (0x0000_0000_0000_0000, 8),
            (0xFFFF_FFFF_FFFF_FFFF, 1),
            (0x0000_0000_0000_0003, 3),
            (0x0000_0000_0000_00FF, 64)
        ]
        for probe in probes {
            let expected = linearSearch(entries, hash: probe.hash, maxDistance: probe.maxDistance)
            let found = Set(tree.query(hash: probe.hash, maxDistance: probe.maxDistance).ids)
            XCTAssertEqual(found, expected, "query(hash: \(probe.hash), maxDistance: \(probe.maxDistance))")
        }
    }

    // Id con lo STESSO hash convivono in un nodo e sono entrambi restituiti (nessuna perdita).
    func test_collidingHashesShareNodeAndAreBothReturned() {
        var tree = BKTree<String>()
        tree.insert("x1", hash: 0x00AB)
        tree.insert("x2", hash: 0x00AB)   // stesso hash
        tree.insert("y", hash: 0xFF00)

        XCTAssertEqual(tree.count, 3)
        let found = Set(tree.query(hash: 0x00AB, maxDistance: 0).ids)
        XCTAssertEqual(found, ["x1", "x2"])
    }

    // Query su albero vuoto → nessun match, nessun confronto.
    func test_emptyTreeYieldsNoMatches() {
        let tree = BKTree<String>()
        XCTAssertTrue(tree.isEmpty)
        let result = tree.query(hash: 0x1234, maxDistance: 5)
        XCTAssertTrue(result.ids.isEmpty)
        XCTAssertEqual(result.comparisons, 0)
    }

    // AC-FSE-H1-2: su cluster ben separati, i confronti di Hamming sono STRETTAMENTE
    // MENO di N (la potatura salta interi sottoalberi) — l'efficienza è un fatto.
    func test_queryDoesFewerComparisonsThanLinearSearch() {
        // Tre cluster a ~32 bit di distanza l'uno dall'altro; 6 membri ciascuno a
        // Hamming 1 dalla propria base → dentro-cluster ≤ 2, fra-cluster ≥ 30.
        let bases: [UInt64] = [
            0x0000_0000_0000_0000,
            0x0000_0000_FFFF_FFFF,
            0xFFFF_FFFF_0000_0000
        ]
        var entries: [(id: Int, hash: UInt64)] = []
        var nextID = 0
        for base in bases {
            for bit in 0..<6 {
                entries.append((id: nextID, hash: base ^ (UInt64(1) << UInt64(bit))))
                nextID += 1
            }
        }
        let total = entries.count   // 18

        var tree = BKTree<Int>()
        for entry in entries { tree.insert(entry.id, hash: entry.hash) }

        // Interrogando la base di ciascun cluster con soglia stretta: la query trova i
        // soli 6 membri di quel cluster ed esegue MENO di N confronti (potatura).
        for base in bases {
            let result = tree.query(hash: base, maxDistance: 3)
            XCTAssertEqual(result.ids.count, 6, "la query deve trovare solo il proprio cluster")
            XCTAssertLessThan(
                result.comparisons,
                total,
                "la potatura per disuguaglianza triangolare deve saltare almeno un sottoalbero"
            )
        }
    }
}
