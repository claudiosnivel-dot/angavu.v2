import Foundation

// FSE-H1 — Clustering delle foto simili a MEMORIA LIMITATA sui dHash a 64 bit.
//
// Origine (bugfix device-test 2026-08-29): il clustering greedy sul feature print
// Vision è O(N²) confronti + O(N) osservazioni Vision trattenute → jetsam su libreria
// reale. Qui il clustering diventa O(N·log N) a memoria limitata: solo interi a 64 bit
// e la struttura ad albero, MAI un'immagine o un feature print trattenuti.
//
// Altitudine invariata (00-INDEX §1bis): aritmetica pura su UInt64, solo Foundation,
// nessun import di piattaforma. Il calcolo REALE del dHash e la conferma Vision sono
// FSE-H2 (Data); la re-inclusione nella scansione unificata è FSE-H4.

// MARK: - Albero BK sui dHash (Burkhard-Keller)

/// Albero metrico BK sui dHash a 64 bit con distanza di Hamming. Sfrutta la
/// disuguaglianza triangolare per trovare i vicini entro una soglia visitando solo
/// un sottoinsieme dei nodi (in media ~O(log N)), invece della ricerca lineare O(N).
///
/// È una struttura di lavoro **a valore** (nodi in un array, figli indicizzati per
/// distanza d'arco): non trattiene immagini né feature print — solo `UInt64` + id.
public struct BKTree<ID> {
    private struct Node {
        let hash: UInt64
        var ids: [ID]
        /// Figli indicizzati per distanza di Hamming dall'arco (chiave) → indice nodo.
        var children: [Int: Int]
    }

    private var nodes: [Node] = []

    public init() {}

    /// `true` finché non è stato inserito alcun hash.
    public var isEmpty: Bool { nodes.isEmpty }

    /// Numero totale di id inseriti (più id possono condividere lo stesso hash).
    public var count: Int { nodes.reduce(0) { $0 + $1.ids.count } }

    /// Inserisce un id associato al suo dHash. Due id con lo STESSO hash convivono
    /// nello stesso nodo (nessuna perdita, nessun duplicato di nodo).
    public mutating func insert(_ id: ID, hash: UInt64) {
        guard !nodes.isEmpty else {
            nodes.append(Node(hash: hash, ids: [id], children: [:]))
            return
        }
        var cursor = 0
        while true {
            let distance = SimilarClustering.hammingDistance(nodes[cursor].hash, hash)
            if distance == 0 {
                nodes[cursor].ids.append(id)
                return
            }
            if let next = nodes[cursor].children[distance] {
                cursor = next
            } else {
                let newIndex = nodes.count
                nodes.append(Node(hash: hash, ids: [id], children: [:]))
                nodes[cursor].children[distance] = newIndex
                return
            }
        }
    }

    /// Trova gli id il cui hash è entro `maxDistance` (Hamming) da `hash`. Riporta anche
    /// il numero di confronti di Hamming eseguiti: la potatura per disuguaglianza
    /// triangolare rende questo numero MINORE della ricerca lineare — un fatto misurabile
    /// (AC-FSE-H1-2), non una frase. `maxDistance` negativo è trattato come 0.
    public func query(hash: UInt64, maxDistance: Int) -> BKTreeMatches<ID> {
        guard !nodes.isEmpty else { return BKTreeMatches(ids: [], comparisons: 0) }
        let ceiling = max(0, maxDistance)
        var matches: [ID] = []
        var comparisons = 0
        var stack = [0]
        while let index = stack.popLast() {
            let node = nodes[index]
            let distance = SimilarClustering.hammingDistance(node.hash, hash)
            comparisons += 1
            if distance <= ceiling {
                matches.append(contentsOf: node.ids)
            }
            // Disuguaglianza triangolare: un figlio a distanza d'arco `edge` dal nodo può
            // contenere match solo se |edge - distance| ≤ ceiling → potatura degli altri.
            let lower = distance - ceiling
            let upper = distance + ceiling
            for (edge, child) in node.children where edge >= lower && edge <= upper {
                stack.append(child)
            }
        }
        return BKTreeMatches(ids: matches, comparisons: comparisons)
    }
}

/// Esito di una query sul BK-tree: gli id entro soglia + i confronti eseguiti (la
/// prova numerica dell'efficienza, AC-FSE-H1-2).
public struct BKTreeMatches<ID> {
    public let ids: [ID]
    public let comparisons: Int

    public init(ids: [ID], comparisons: Int) {
        self.ids = ids
        self.comparisons = comparisons
    }
}

// MARK: - Clustering per dHash a memoria limitata

public extension SimilarClustering {
    /// Raggruppa i candidati per vicinanza dHash (Hamming ≤ `maxHammingDistance`) via
    /// BK-tree, in O(N·log N) senza trattenere immagini né feature print. La partizione
    /// è le **componenti connesse** del grafo "vicini entro soglia": deterministica e
    /// indipendente dall'ordine d'ingresso, IDENTICA alla forza bruta sulla Hamming
    /// (AC-FSE-H1-4) — il BK-tree accelera, non cambia il risultato.
    ///
    /// Un candidato **senza dHash** resta singleton: non essendo verificabile per
    /// vicinanza, non viene mai dichiarato simile (nessun falso "via libera",
    /// AC-FSE-H1-3). Ordine stabile: membri per indice d'ingresso, cluster per indice
    /// minimo dei loro membri.
    static func clustersByHash(
        of candidates: [SimilarityCandidate],
        maxHammingDistance: Int
    ) -> [SimilarCluster] {
        guard !candidates.isEmpty else { return [] }
        let ceiling = max(0, maxHammingDistance)
        let total = candidates.count

        // Union-find sugli indici d'input (componenti connesse deterministiche).
        var parent = Array(0..<total)
        func root(of node: Int) -> Int {
            var current = node
            while parent[current] != current { current = parent[current] }
            var walker = node
            while parent[walker] != current {
                let next = parent[walker]
                parent[walker] = current
                walker = next
            }
            return current
        }
        func union(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            // Radice = indice minore → canonica, indipendente dall'ordine delle union.
            parent[max(lhsRoot, rhsRoot)] = min(lhsRoot, rhsRoot)
        }

        // Il BK-tree indicizza SOLO i candidati con dHash: gli altri restano singleton
        // per costruzione (mai interrogati, mai uniti).
        var tree = BKTree<Int>()
        for (index, candidate) in candidates.enumerated() {
            if let hash = candidate.dHash { tree.insert(index, hash: hash) }
        }
        for (index, candidate) in candidates.enumerated() {
            guard let hash = candidate.dHash else { continue }
            for neighbour in tree.query(hash: hash, maxDistance: ceiling).ids where neighbour != index {
                union(index, neighbour)
            }
        }

        // Raggruppa per radice; l'iterazione ascendente tiene i membri (e il .first di
        // ogni gruppo) in ordine d'indice → ordinamento cluster deterministico.
        var groups: [Int: [Int]] = [:]
        for index in 0..<total {
            groups[root(of: index), default: []].append(index)
        }
        return groups
            .sorted { ($0.value.first ?? 0) < ($1.value.first ?? 0) }
            .map { SimilarCluster(members: $0.value.map { candidates[$0] }) }
    }
}
