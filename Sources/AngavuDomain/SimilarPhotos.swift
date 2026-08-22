import Foundation

// Macrotask `similar_photos` — modello di dominio PURO delle foto simili.
//
// Quattro pezzi, uno per task atomico, tutti senza alcun tipo di piattaforma
// (altitudine `domain ↛ data`, 00-INDEX §1bis):
//   • T-040 port `FeaturePrinting` + distanza semantica come valore puro;
//   • T-041 clustering per soglia con fallback dHash/Hamming, a blocchi cancellabili (T-004);
//   • T-042 port `QualityScoring` + regola best-of-cluster ("tieni la migliore");
//   • T-043 `DeletionProposal { keep, removable }` per cluster (solo dati per safety_net).
//
// Come `exact_duplicates`, il Domain NON importa Vision: il feature print e il suo
// `computeDistance` vivono dietro un port implementato nel Data layer; qui arriva
// solo un `Float` di distanza. Il dHash è un valore puro a 64 bit: la distanza di
// Hamming del fallback è aritmetica pura, quindi resta nel Domain e testabile su Linux.

// MARK: - T-040 — Feature print dietro adapter e distanza semantica

/// Port del feature print (architettura esagonale, come `AssetContentHashing`).
/// L'implementazione reale (Vision: `VNGenerateImageFeaturePrintRequest` +
/// `computeDistance`) vive nel Data layer; il Domain riceve SOLO distanze pure.
///
/// Sincrono e agnostico, come il motore T-004: il chiamante lo mette off-main.
public protocol FeaturePrinting {
    /// Distanza semantica fra i feature print di due asset (in produzione, il
    /// `computeDistance` di Vision), oppure `nil` se almeno uno dei due non ha un
    /// feature print calcolabile on-device (es. originale solo in iCloud). Un asset
    /// senza feature print non viene mai dichiarato simile per via semantica: il
    /// clustering ricadrà sul dHash (T-041), mai su un falso "via libera".
    func distance(between lhs: LibraryAsset, and rhs: LibraryAsset) throws -> Float?
}

/// Interrogazione di dominio della distanza semantica fra due asset. È un seam
/// sottile sopra il port: il Domain vede un `Float?`, mai un tipo di Vision (AC-040-1/2).
public enum SemanticDistance {
    /// Distanza semantica fra due asset secondo il provider, o `nil` se non
    /// calcolabile per almeno uno dei due.
    public static func between(
        _ lhs: LibraryAsset,
        _ rhs: LibraryAsset,
        using provider: FeaturePrinting
    ) throws -> Float? {
        try provider.distance(between: lhs, and: rhs)
    }
}

// MARK: - T-041 — Clustering per soglia con fallback dHash

/// Candidato al clustering di simili: l'asset più il suo dHash percettivo a 64 bit,
/// usato come fallback economico quando il feature print Vision non è disponibile.
/// Il dHash è un valore PURO: la distanza di Hamming è aritmetica, calcolata nel
/// Domain senza dipendere da Vision. `nil` se il dHash non è calcolabile.
public struct SimilarityCandidate: Equatable, Sendable {
    public let asset: LibraryAsset
    /// dHash percettivo a 64 bit (fallback), o `nil` se non calcolabile.
    public let dHash: UInt64?

    public init(asset: LibraryAsset, dHash: UInt64?) {
        self.asset = asset
        self.dHash = dHash
    }
}

/// Soglie di similarità. La distanza semantica (feature print) e la distanza di
/// Hamming (dHash) vivono su **scale diverse**, quindi hanno soglie separate: non
/// vanno mai confuse in un unico numero.
public struct SimilarityThresholds: Equatable, Sendable {
    /// Distanza semantica massima (inclusa) per considerare due asset simili.
    public let semantic: Float
    /// Distanza di Hamming massima (inclusa), in bit differenti su 64, per il fallback dHash.
    public let hamming: Int

    public init(semantic: Float, hamming: Int) {
        self.semantic = semantic
        self.hamming = max(0, hamming)
    }
}

/// Cluster di foto simili. Il primo elemento è il **rappresentante** usato dal
/// clustering incrementale per il confronto (greedy, deterministico per ordine
/// d'ingresso). Un cluster può avere un solo membro (nulla da proporre, T-043).
public struct SimilarCluster: Equatable, Sendable {
    public let members: [SimilarityCandidate]

    public init(members: [SimilarityCandidate]) {
        self.members = members
    }

    /// Rappresentante del cluster (il primo membro), o `nil` se degenere/vuoto.
    public var representative: SimilarityCandidate? { members.first }
}

/// Clustering puro delle foto simili per soglia, con fallback dHash.
public enum SimilarClustering {
    /// Distanza di Hamming fra due dHash a 64 bit: numero di bit differenti.
    /// Aritmetica pura (nessuna dipendenza da Vision), 0…64.
    public static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    /// Decide se due candidati sono simili entro soglia. **Priorità** al feature
    /// print semantico; se non disponibile per almeno uno (distanza `nil`),
    /// **fallback** al dHash (Hamming). Se manca anche il dHash per uno dei due →
    /// NON simili: mai un falso "via libera" su un asset non verificabile (AC-041-2).
    static func areSimilar(
        _ lhs: SimilarityCandidate,
        _ rhs: SimilarityCandidate,
        provider: FeaturePrinting,
        thresholds: SimilarityThresholds
    ) throws -> Bool {
        if let semantic = try provider.distance(between: lhs.asset, and: rhs.asset) {
            return semantic <= thresholds.semantic
        }
        // Fallback dHash: serve il dHash per ENTRAMBI.
        guard let lhsHash = lhs.dHash, let rhsHash = rhs.dHash else { return false }
        return hammingDistance(lhsHash, rhsHash) <= thresholds.hamming
    }

    /// Raggruppa i candidati in cluster di simili con un passaggio incrementale
    /// **greedy** e deterministico: ogni candidato entra nel primo cluster il cui
    /// rappresentante è simile entro soglia; se nessuno lo è, apre un nuovo cluster.
    /// Gli asset oltre soglia finiscono così in cluster distinti (AC-041-1).
    ///
    /// L'esecuzione è a blocchi cancellabili (motore T-004): la cancellazione al
    /// confine di un blocco lascia i candidati residui **non processati** (AC-041-3),
    /// e l'esito porta con sé il progresso raggiunto. La partizione include anche i
    /// singleton (un cluster da un solo asset): li consuma T-043.
    public static func clusters(
        of candidates: [SimilarityCandidate],
        provider: FeaturePrinting,
        thresholds: SimilarityThresholds,
        chunkSize: Int = 64,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<[SimilarCluster]> {
        let engine = ChunkedAnalysis<SimilarityCandidate, [SimilarCluster]>(
            chunkSize: chunkSize,
            initial: []
        ) { clusters, candidate in
            var next = clusters
            for index in next.indices {
                guard let representative = next[index].representative else { continue }
                if try areSimilar(candidate, representative, provider: provider, thresholds: thresholds) {
                    next[index] = SimilarCluster(members: next[index].members + [candidate])
                    return next
                }
            }
            // Nessun cluster simile: il candidato apre il proprio cluster.
            next.append(SimilarCluster(members: [candidate]))
            return next
        }
        return engine.run(over: candidates, cancellation: cancellation, progress: progress)
    }
}

// MARK: - T-042 — Punteggio qualità per "tieni la migliore"

/// Punteggio di qualità di un asset, con onestà esplicita sui termini disponibili.
/// La `aesthetics` è OPZIONALE (solo iOS 18, progressive enhancement): su iOS 17 è
/// `nil` e il punteggio aggregato la omette senza fallire (AC-042-2).
public struct QualityScore: Equatable, Sendable {
    /// Nitidezza (più alto = più nitido). Sempre presente.
    public let sharpness: Double
    /// Qualità dei volti (0…1), se rilevabile; altrimenti `nil`.
    public let faceQuality: Double?
    /// Aesthetics score (solo iOS 18); `nil` dove non disponibile. Mai un requisito.
    public let aesthetics: Double?

    public init(sharpness: Double, faceQuality: Double?, aesthetics: Double?) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.aesthetics = aesthetics
    }

    /// Punteggio aggregato: somma dei soli termini **disponibili**. L'assenza di un
    /// termine (volti non rilevati, aesthetics su iOS 17) non fa fallire il calcolo
    /// né penalizza artificialmente: quel termine semplicemente non concorre.
    public var overall: Double {
        sharpness + (faceQuality ?? 0) + (aesthetics ?? 0)
    }
}

/// Port del punteggio di qualità (esagonale). L'implementazione reale (Core
/// Image/vImage per la nitidezza, Vision per volti/aesthetics) vive nel Data layer;
/// il Domain riceve `QualityScore` come valore puro.
public protocol QualityScoring {
    /// Punteggio di qualità dell'asset. Può lanciare se l'analisi on-device fallisce.
    func score(for asset: LibraryAsset) throws -> QualityScore
}

/// Candidato accoppiato al suo punteggio di qualità, per il ranking di cluster.
public struct ScoredCandidate: Equatable, Sendable {
    public let candidate: SimilarityCandidate
    public let score: QualityScore

    public init(candidate: SimilarityCandidate, score: QualityScore) {
        self.candidate = candidate
        self.score = score
    }
}

/// Regola pura "tieni la migliore": ordina i candidati di un cluster per qualità.
public enum ClusterQualityRanking {
    /// Ordina i membri del cluster dal **migliore al peggiore** per punteggio
    /// aggregato. A parità di punteggio l'ordine è stabile per `id` crescente
    /// (deterministico), così il keep di un cluster non dipende dall'ordine d'ingresso.
    public static func ranked(
        _ cluster: SimilarCluster,
        scoring: QualityScoring
    ) throws -> [ScoredCandidate] {
        let scored = try cluster.members.map { member in
            ScoredCandidate(candidate: member, score: try scoring.score(for: member.asset))
        }
        return scored.sorted { lhs, rhs in
            if lhs.score.overall != rhs.score.overall {
                return lhs.score.overall > rhs.score.overall
            }
            return lhs.candidate.asset.id < rhs.candidate.asset.id
        }
    }
}

// MARK: - T-043 — Proposta di eliminazione per cluster di simili

/// Proposta per un cluster di simili: un asset da tenere (il migliore, `keep`) e
/// gli altri marcati rimovibili. NESSUNA eliminazione qui — è solo dati per la rete
/// di sicurezza (`safety_net`), che passa sempre dall'anteprima obbligatoria (T-050).
/// La proposta è reversibile: non innesca alcuna transizione di eliminazione.
public struct DeletionProposal: Equatable, Sendable {
    /// L'asset che si propone di tenere (il migliore del cluster).
    public let keep: SimilarityCandidate
    /// Gli asset che si propone di rimuovere (mai eliminati qui).
    public let removable: [SimilarityCandidate]

    public init(keep: SimilarityCandidate, removable: [SimilarityCandidate]) {
        self.keep = keep
        self.removable = removable
    }
}

/// Composizione pura delle proposte di eliminazione per cluster di simili.
public enum SimilarDeletionProposal {
    /// Compone la proposta di un cluster usando il ranking di qualità (T-042):
    /// `keep` = il migliore, `removable` = tutti gli altri. Un cluster con un solo
    /// asset ha `removable` vuoto — nulla da proporre in eliminazione (AC-043-2).
    /// Restituisce `nil` per un cluster vuoto (nessun keep possibile).
    public static func compose(
        for cluster: SimilarCluster,
        scoring: QualityScoring
    ) throws -> DeletionProposal? {
        let ranked = try ClusterQualityRanking.ranked(cluster, scoring: scoring)
        guard let best = ranked.first else { return nil }
        return DeletionProposal(
            keep: best.candidate,
            removable: ranked.dropFirst().map(\.candidate)
        )
    }

    /// Comodità: una proposta per ogni cluster (i cluster vuoti sono omessi).
    public static func proposals(
        for clusters: [SimilarCluster],
        scoring: QualityScoring
    ) throws -> [DeletionProposal] {
        try clusters.compactMap { try compose(for: $0, scoring: scoring) }
    }
}
