import Foundation

// FSE-H2 (Domain) — Raggruppamento burst nativo (Tier 0), pura logica.
//
// Le raffiche (burst) sono già identificate da PhotoKit con un `burstIdentifier`: gli
// scatti di una stessa raffica lo condividono, e uno è marcato come scelto (`.userPick`
// se l'utente l'ha scelto, `.autoPick` se il sistema). È il segnale di similarità PIÙ
// ECONOMICO in assoluto — metadato locale, ZERO Vision, ZERO dHash, ZERO decodifica —
// quindi è il Tier 0 del funnel dei simili (FAST-SCAN-ENGINE-PLAN §FSE-H): raggruppa le
// raffiche prima ancora di calcolare qualunque hash percettivo.
//
// Qui vive SOLO la logica pura (raggruppamento per identificatore + scelta del keep dal
// pick nativo), testabile su Linux con id finti (AC-FSE-H2-2). L'estrazione del
// `burstIdentifier`/pick dai PHAsset e la fusione dei burst nella scansione unificata
// sono il cablaggio device di FSE-H4 (dichiarato non coperto qui, L-COL-006).
//
// Altitudine (00-INDEX §1bis): Domain puro — solo Foundation, nessun tipo di Photos.

/// Scelta nativa dello scatto rappresentativo di una raffica, da PhotoKit
/// (`PHAssetBurstSelectionType`). Guida il keep senza alcun punteggio di qualità: per un
/// burst è il segnale dell'utente/sistema, non una stima.
public enum BurstSelection: String, Equatable, Sendable {
    /// L'utente ha scelto esplicitamente questo scatto della raffica.
    case userPick
    /// Il sistema (PhotoKit) ha proposto questo scatto come migliore della raffica.
    case autoPick
    /// Nessuna scelta esplicita.
    case none
}

/// Asset annotato col suo `burstIdentifier` nativo e la scelta della raffica. Il
/// `burstIdentifier` è `nil` per gli scatti singoli (non fanno parte di alcuna raffica).
public struct BurstAsset: Equatable, Sendable {
    public let asset: LibraryAsset
    /// Identificatore di raffica nativo (in PhotoKit: `PHAsset.burstIdentifier`), o
    /// `nil` se lo scatto non fa parte di una raffica.
    public let burstIdentifier: String?
    /// Scelta nativa della raffica per questo scatto.
    public let selection: BurstSelection

    public init(asset: LibraryAsset, burstIdentifier: String?, selection: BurstSelection = .none) {
        self.asset = asset
        self.burstIdentifier = burstIdentifier
        self.selection = selection
    }
}

/// Raffica raggruppata: gli scatti che condividono lo stesso `burstIdentifier`.
public struct BurstCluster: Equatable, Sendable {
    public let members: [BurstAsset]

    public init(members: [BurstAsset]) {
        self.members = members
    }

    /// Scatto da tenere: guidato dal pick NATIVO — `.userPick` batte `.autoPick`, che
    /// batte il primo per ordine d'ingresso (mai una scelta arbitraria). Per un burst il
    /// keep è il segnale dell'utente/sistema, non un punteggio di qualità.
    public var keep: BurstAsset? {
        members.first { $0.selection == .userPick }
            ?? members.first { $0.selection == .autoPick }
            ?? members.first
    }

    /// Gli altri scatti della raffica (tutti tranne il keep): proponibili in
    /// eliminazione. Rimuove esattamente la PRIMA occorrenza del keep scelto.
    public var removable: [BurstAsset] {
        guard let keep else { return [] }
        var removed = false
        return members.filter { member in
            if !removed && member == keep {
                removed = true
                return false
            }
            return true
        }
    }
}

/// Raggruppamento puro delle raffiche per `burstIdentifier` nativo.
public enum BurstGrouping {
    /// Raggruppa gli asset in raffiche: quelli con lo STESSO `burstIdentifier` (non
    /// `nil`) finiscono nello stesso cluster; uno scatto senza raffica (`nil`) o con un
    /// identificatore unico resta singleton (AC-FSE-H2-2). Nessun calcolo Vision/dHash:
    /// solo il confronto dei metadati.
    ///
    /// Ordine deterministico e indipendente da riordini interni al burst: i cluster sono
    /// ordinati per indice di PRIMA APPARIZIONE dei loro membri; i membri di un cluster
    /// restano in ordine d'ingresso.
    public static func groups(of assets: [BurstAsset]) -> [BurstCluster] {
        var indicesByBurst: [String: [Int]] = [:]
        var firstIndexByBurst: [String: Int] = [:]
        // Ogni cluster è (indice minimo dei membri, indici in ordine d'ingresso).
        var clusters: [(minIndex: Int, indices: [Int])] = []

        for (index, member) in assets.enumerated() {
            guard let burst = member.burstIdentifier else {
                // Scatto singolo: singleton immediato, in posizione d'ingresso.
                clusters.append((index, [index]))
                continue
            }
            if indicesByBurst[burst] == nil { firstIndexByBurst[burst] = index }
            indicesByBurst[burst, default: []].append(index)
        }
        for (burst, indices) in indicesByBurst {
            clusters.append((firstIndexByBurst[burst] ?? indices.first ?? 0, indices))
        }

        return clusters
            .sorted { $0.minIndex < $1.minIndex }
            .map { BurstCluster(members: $0.indices.map { assets[$0] }) }
    }

    /// Proposta di eliminazione da una raffica: `keep` = lo scatto scelto dal pick
    /// nativo, `removable` = gli altri. NESSUNA eliminazione qui — è solo dati per la
    /// rete di sicurezza (`safety_net`), che passa sempre dall'anteprima obbligatoria
    /// (T-050). I candidati non portano dHash (il keep di un burst è nativo, non per
    /// vicinanza percettiva). `nil` per una raffica vuota (nessun keep possibile).
    public static func proposal(for cluster: BurstCluster) -> DeletionProposal? {
        guard let keep = cluster.keep else { return nil }
        return DeletionProposal(
            keep: SimilarityCandidate(asset: keep.asset, dHash: nil),
            removable: cluster.removable.map { SimilarityCandidate(asset: $0.asset, dHash: nil) }
        )
    }
}
