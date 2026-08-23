import AngavuDomain
import Observation

// T-113 (wiring) — Schermata categorie: proposte dei rilevatori → liste
// keep/removable, con OGNI eliminazione instradata alla rete di sicurezza.
//
// Un solo view-model riusabile per tutte le categorie (duplicati esatti, foto
// simili, video grandi/vecchi, sfocate): le proposte dei rilevatori hanno tipi
// diversi ma si normalizzano tutte in `CategoryReview` (id da tenere vs id
// eliminabili). L'azione di eliminazione apre SEMPRE il `DeletionFlow` (T-050):
// preview → accept → confirm sull'insieme selezionato. Nessun percorso salta il
// gate d'anteprima; i keep non sono mai eliminabili. Nessuna logica di dominio
// nuova: solo cablaggio delle proposte già verdi.

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

@Observable
public final class CategoryReviewViewModel {
    public private(set) var review: CategoryReview
    /// Rete di sicurezza condivisa (T-050). Esposta: la View avvia poi
    /// `beginDeleting()` a valle della conferma. Il delete reale (adapter) è fuori
    /// scope qui.
    public private(set) var flow: DeletionFlow = DeletionFlow()

    public init(review: CategoryReview) {
        self.review = review
    }

    /// Righe presentabili (keep vs removable).
    public var rows: [CategoryReviewRow] { review.rows }

    /// Richiede l'eliminazione degli id dati instradandoli al `DeletionFlow`:
    /// preview → accept → confirm. Invarianti:
    ///  • solo id **removable** sono eleggibili (i keep sono filtrati: mai eliminati);
    ///  • selezione vuota (o di soli keep) ⇒ azione rifiutata, nessuna anteprima
    ///    vuota (AC-113-2).
    /// Restituisce `true` sse il flusso è arrivato a `confirmed` sull'insieme
    /// eleggibile (AC-113-1).
    @discardableResult
    public func requestDeletion(of ids: [String]) -> Bool {
        let removable = Set(review.removableIds)
        let eligible = ids.filter { removable.contains($0) }
        guard !eligible.isEmpty else { return false }
        guard flow.presentPreview(for: eligible) else { return false }
        flow.acceptPreview()
        return flow.confirm()
    }

    /// Comodità: elimina tutti i removable della proposta (mai i keep).
    @discardableResult
    public func requestDeletionOfAllRemovable() -> Bool {
        requestDeletion(of: review.removableIds)
    }
}
