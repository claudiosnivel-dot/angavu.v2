import Foundation

// Macrotask `exact_duplicates` — modello di dominio PURO dei duplicati esatti.
//
// Tre pezzi, uno per task atomico, tutti senza alcun tipo di piattaforma
// (altitudine `domain ↛ data`, 00-INDEX §1bis):
//   • T-030 raggruppamento candidati per dimensione byte (riduce il costo hashing);
//   • T-031 cluster per SHA-256 identico, hashing a blocchi cancellabile (T-004);
//   • T-032 selezione keep-one deterministica per cluster (solo proposta, mai
//     eliminazione: l'eliminazione passa da safety_net e dall'anteprima obbligatoria).
//
// Il Domain NON calcola lo SHA-256 (niente CryptoKit, che è Apple-only): un port
// del Data layer legge i byte on-device e produce il digest; qui si raggruppa per
// digest identico. Così l'intera logica resta testabile su Linux, senza device.

// MARK: - T-030 — Raggruppamento candidati per dimensione

/// Gruppo di asset che condividono la stessa dimensione in byte: candidati a
/// duplicato esatto. Due file con byte diversi non possono avere la stessa
/// dimensione uguale al byte, quindi la dimensione è il primo filtro economico
/// prima dell'hashing (che è costoso).
public struct SizeCandidateGroup: Equatable, Sendable {
    /// Dimensione in byte condivisa dagli asset del gruppo.
    public let byteSize: Int64
    /// Asset con questa dimensione (>= 2 per costruzione dell'aggregatore).
    public let assets: [SizedAsset]

    public init(byteSize: Int64, assets: [SizedAsset]) {
        self.byteSize = byteSize
        self.assets = assets
    }
}

/// Raggruppamento puro degli asset per dimensione byte.
public enum SizeCandidateGrouping {
    /// Raggruppa gli asset per dimensione in byte e restituisce SOLO i gruppi con
    /// cardinalità > 1: un asset di dimensione unica non può avere un duplicato,
    /// quindi non c'è nulla da hashare su di esso (AC-030-1/2).
    ///
    /// L'ordine dei gruppi è per dimensione crescente (stabile e deterministico);
    /// dentro ogni gruppo l'ordine d'ingresso è preservato. La marcatura
    /// exact/estimated del `ByteSize` non conta qui: la dimensione è solo un
    /// filtro di candidatura; la verità la stabilisce l'hashing (T-031).
    public static func candidateGroups(_ items: [SizedAsset]) -> [SizeCandidateGroup] {
        var buckets: [Int64: [SizedAsset]] = [:]
        for item in items {
            buckets[item.size.bytes, default: []].append(item)
        }
        return buckets.keys.sorted().compactMap { key -> SizeCandidateGroup? in
            guard let group = buckets[key], group.count > 1 else { return nil }
            return SizeCandidateGroup(byteSize: key, assets: group)
        }
    }
}

// MARK: - T-031 — Hashing SHA-256 dei candidati e cluster di identici

/// Digest opaco del contenuto di un asset (in produzione uno SHA-256 esadecimale).
/// Il Domain non lo calcola — lo riceve da un port del Data layer — e si limita a
/// raggruppare per digest identico: così resta puro (niente CryptoKit) e testabile.
public struct AssetDigest: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// Port di hashing del contenuto di un asset (architettura esagonale, come
/// `AssetIndexReading/Writing`). L'implementazione reale vive nel Data layer
/// (legge i byte via PhotoKit, calcola lo SHA-256); nei test è un fake.
///
/// Sincrono e agnostico, come il motore T-004: il chiamante lo mette off-main.
public protocol AssetContentHashing {
    /// Digest del contenuto dell'asset, o `nil` se i byte non sono leggibili
    /// on-device (es. originale solo in iCloud): un asset non verificabile non
    /// viene mai dichiarato duplicato (nessun falso "via libera").
    func digest(for asset: LibraryAsset) throws -> AssetDigest?
}

/// Cluster di duplicati ESATTI: asset con lo stesso digest di contenuto (>= 2).
public struct ExactDuplicateCluster: Equatable, Sendable {
    /// Digest condiviso dagli asset del cluster.
    public let digest: AssetDigest
    /// Dimensione in byte condivisa (ereditata dai gruppi candidati).
    public let byteSize: Int64
    /// Asset identici byte-per-byte (>= 2 per costruzione).
    public let assets: [SizedAsset]

    public init(digest: AssetDigest, byteSize: Int64, assets: [SizedAsset]) {
        self.digest = digest
        self.byteSize = byteSize
        self.assets = assets
    }
}

/// Esito per-candidato dell'hashing (FSE-D2): il candidato e il suo digest (o `nil`
/// se non hashabile on-device). Prodotto in parallelo dal motore per-item, poi
/// raggruppato in ordine d'input.
private struct HashedCandidate: Equatable {
    let item: SizedAsset
    let digest: AssetDigest?
}

/// Clustering puro dei duplicati esatti a partire dai gruppi candidati.
public enum ExactDuplicateClustering {
    /// Hasha i candidati a blocchi cancellabili (T-004) e forma i cluster di asset
    /// con digest identico. Solo i gruppi con >= 2 asset diventano cluster; gli
    /// asset non hashabili (`digest == nil`) sono esclusi (AC-031-1). La
    /// cancellazione al confine di un blocco lascia i candidati residui non
    /// hashati (AC-031-2): l'esito porta con sé il progresso raggiunto.
    ///
    /// L'ordine dei cluster è deterministico: per dimensione byte, poi per digest.
    ///
    /// FSE-D2 — L'hashing è INDIPENDENTE per candidato: si calcola con un motore
    /// per-item iniettabile (`PerItemAnalysis`, default seriale), poi si raggruppa per
    /// digest identico (riduzione PURA che preserva l'ordine d'input). Col motore
    /// concorrente ogni digest gira in parallelo e i cluster sono IDENTICI al seriale
    /// (stessi digest, stesso ordine di raggruppamento) — AC-FSE-D2-1.
    public static func clusters(
        from groups: [SizeCandidateGroup],
        hasher: AssetContentHashing,
        chunkSize: Int = 64,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in },
        analysis: PerItemAnalysis? = nil
    ) -> AnalysisOutcome<[ExactDuplicateCluster]> {
        let candidates = groups.flatMap { $0.assets }
        let engine = analysis ?? .serial(chunkSize: chunkSize)

        // Fase indipendente: il digest di ogni candidato, in parallelo o in serie.
        let outcome = engine.map(candidates, cancellation: cancellation, progress: progress) { item in
            HashedCandidate(item: item, digest: try hasher.digest(for: item.asset))
        }

        switch outcome {
        case .completed(let hashed):
            // Riduzione pura ordine-preservante: identica alla piega seriale storica.
            var byDigest: [AssetDigest: [SizedAsset]] = [:]
            for entry in hashed {
                if let digest = entry.digest {
                    byDigest[digest, default: []].append(entry.item)
                }
            }
            return .completed(makeClusters(byDigest))
        case .cancelled(let at):
            return .cancelled(at: at)
        case .failed(let reason, let at):
            return .failed(reason: reason, at: at)
        }
    }

    /// Trasforma la mappa digest→asset nei soli cluster con più di un asset,
    /// in ordine deterministico (dimensione, poi digest).
    private static func makeClusters(_ byDigest: [AssetDigest: [SizedAsset]]) -> [ExactDuplicateCluster] {
        byDigest.compactMap { digest, assets -> ExactDuplicateCluster? in
            guard assets.count > 1, let first = assets.first else { return nil }
            return ExactDuplicateCluster(digest: digest, byteSize: first.size.bytes, assets: assets)
        }
        .sorted { ($0.byteSize, $0.digest.value) < ($1.byteSize, $1.digest.value) }
    }
}

// MARK: - T-032 — Selezione keep-one per cluster

/// Proposta per un cluster: un asset da tenere (keep) e gli altri marcati
/// rimovibili. NESSUNA eliminazione qui — è solo dati per la rete di sicurezza
/// (`safety_net`), che passa sempre dall'anteprima obbligatoria (T-050).
public struct KeepOneProposal: Equatable, Sendable {
    /// L'asset che si propone di tenere.
    public let keep: SizedAsset
    /// Gli asset che si propone di rimuovere (mai eliminati qui).
    public let removable: [SizedAsset]

    public init(keep: SizedAsset, removable: [SizedAsset]) {
        self.keep = keep
        self.removable = removable
    }
}

/// Regola pura di selezione keep-one per cluster di duplicati esatti.
public enum KeepOneSelection {
    /// Sceglie deterministicamente il keep di un cluster e marca i restanti
    /// removable. Regola: si tiene l'asset con `id` minore in ordine
    /// lessicografico — arbitraria ma stabile, così a parità d'input il keep è
    /// sempre lo stesso (AC-032-2). Trattandosi di duplicati ESATTI (byte
    /// identici) ogni copia vale l'altra: nessuna è "migliore".
    ///
    /// Restituisce `nil` per un cluster degenere senza asset (non dovrebbe
    /// esistere per costruzione, ma evitiamo un force-unwrap).
    public static func propose(for cluster: ExactDuplicateCluster) -> KeepOneProposal? {
        let ordered = cluster.assets.sorted { $0.asset.id < $1.asset.id }
        guard let keep = ordered.first else { return nil }
        return KeepOneProposal(keep: keep, removable: Array(ordered.dropFirst()))
    }

    /// Comodità: una proposta per ogni cluster (i degeneri sono omessi).
    public static func proposals(for clusters: [ExactDuplicateCluster]) -> [KeepOneProposal] {
        clusters.compactMap { propose(for: $0) }
    }
}
