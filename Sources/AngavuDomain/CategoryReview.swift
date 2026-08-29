import Foundation

// FSE-J2 — Modello di dominio della review di categoria (Domain puro).
//
// Spostato qui da AngavuFeatures (era in `CategoryReviewViewModel.swift`) perché è
// logica pura, indipendente dalla piattaforma: gli id da tenere vs quelli
// eliminabili, con la normalizzazione dalle proposte dei rilevatori (tutte già in
// Domain) e la potatura chirurgica `removing(ids:)`. Il view-model osservabile e il
// cablaggio dell'eliminazione restano in Features. Tenere il tipo in Domain rende
// oracolabile `removing(ids:)` dai test di dominio (AC-FSE-J2-1) e conferma
// l'altitudine: la review non vede né PhotoKit né SwiftUI.

/// Disposizione di una riga nella review di categoria.
public enum CategoryDisposition: Equatable, Sendable {
    /// Da tenere: mai eliminabile.
    case keep
    /// Eliminabile: candidabile all'eliminazione via rete di sicurezza.
    case removable
}

/// Riga presentabile: un asset e la sua disposizione.
public struct CategoryReviewRow: Equatable, Sendable {
    public let id: String
    public let disposition: CategoryDisposition

    public init(id: String, disposition: CategoryDisposition) {
        self.id = id
        self.disposition = disposition
    }
}

/// Modello normalizzato di una review di categoria: gli id da tenere e quelli
/// eliminabili, indipendente dal tipo concreto di proposta del rilevatore.
public struct CategoryReview: Equatable, Sendable {
    public let keepIds: [String]
    public let removableIds: [String]

    public init(keepIds: [String], removableIds: [String]) {
        self.keepIds = keepIds
        self.removableIds = removableIds
    }

    /// Righe presentabili: prima i keep, poi i removable (ordine stabile).
    public var rows: [CategoryReviewRow] {
        keepIds.map { CategoryReviewRow(id: $0, disposition: .keep) }
            + removableIds.map { CategoryReviewRow(id: $0, disposition: .removable) }
    }

    /// FSE-J1/J2 — Toglie gli id dati da keep e removable (ordine stabile del resto).
    /// Usata da FSE-J1 per aggiornare la review dopo un'eliminazione REALE riuscita, e
    /// riusata da FSE-J2 per la potatura chirurgica della cache. No-op su insieme vuoto.
    public func removing(ids: Set<String>) -> CategoryReview {
        guard !ids.isEmpty else { return self }
        return CategoryReview(
            keepIds: keepIds.filter { !ids.contains($0) },
            removableIds: removableIds.filter { !ids.contains($0) }
        )
    }

    // MARK: - Normalizzazione dalle proposte dei rilevatori

    /// Duplicati esatti (T-032): si tiene uno, il resto è eliminabile.
    public static func from(keepOne proposal: KeepOneProposal) -> CategoryReview {
        CategoryReview(
            keepIds: [proposal.keep.asset.id],
            removableIds: proposal.removable.map(\.asset.id)
        )
    }

    /// Foto simili (T-043): si tiene la migliore del cluster, il resto è eliminabile.
    public static func from(similar proposal: DeletionProposal) -> CategoryReview {
        CategoryReview(
            keepIds: [proposal.keep.asset.id],
            removableIds: proposal.removable.map(\.asset.id)
        )
    }

    /// Video grandi/vecchi, screenshot, screen recording (T-062): eliminazione
    /// diretta, nessun keep.
    public static func from(bulk proposal: BulkDeletionProposal) -> CategoryReview {
        CategoryReview(keepIds: [], removableIds: proposal.removableIds)
    }

    /// Foto sfocate (T-071): le sfocate sono eliminabili, nessun keep.
    public static func fromBlurry(_ assets: [LibraryAsset]) -> CategoryReview {
        CategoryReview(keepIds: [], removableIds: assets.map(\.id))
    }
}
