import AngavuData
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

// FSE-J2 — `CategoryDisposition`, `CategoryReviewRow` e `CategoryReview` (col loro
// `removing(ids:)` e le factory `from(...)`) sono ora in AngavuDomain
// (`CategoryReview.swift`): logica pura, oracolabile dai test di dominio. Qui
// restano il view-model osservabile e la policy di selezione, che dipendono dai
// port del Data layer (`AssetDeleting`).

/// A-2 — Policy PURA della preselezione. La selezione iniziale è **tutti i
/// removable**: per screenshot e video grandi/vecchi è "tutto preselezionato,
/// deselezioni ciò che tieni" (opt-out); per duplicati e simili è "solo la peggiore",
/// perché la migliore vive nei `keepIds` e non compare mai fra i removable. In
/// entrambi i casi `Set(removableIds)` è la preselezione giusta; i keep non sono mai
/// selezionabili (protetti per costruzione).
public enum CategorySelectionPolicy {
    public static func initialSelection(for review: CategoryReview) -> Set<String> {
        Set(review.removableIds)
    }
}

@Observable
public final class CategoryReviewViewModel {
    public private(set) var review: CategoryReview
    /// A-3 — Metadati per-id (kind/data) per le etichette umane, dal `CategoryReviewSource`.
    /// Vuoto quando non forniti (i vecchi test costruiscono col solo `review`).
    public private(set) var assets: [String: LibraryAsset]
    /// A-2 — Selezione per-elemento (solo id removable). Preselezionata via policy.
    public private(set) var selection: Set<String>
    /// Rete di sicurezza condivisa (T-050). Esposta: la View avvia poi
    /// `beginDeleting()` a valle della conferma. Il delete reale (adapter) è fuori
    /// scope qui.
    public private(set) var flow: DeletionFlow = DeletionFlow()
    /// FSE-J1 — Eliminazione reale iniettata (censimento C1). Default null-object
    /// `NoAssetDeleter` (i vecchi test costruiscono senza deleter e non lo invocano); la
    /// View reale passa `environment.assetDeleter` (PhotoKit + allineamento indice).
    private let deleter: any AssetDeleting

    public init(
        review: CategoryReview,
        assets: [String: LibraryAsset] = [:],
        deleter: any AssetDeleting = NoAssetDeleter()
    ) {
        self.review = review
        self.assets = assets
        self.selection = CategorySelectionPolicy.initialSelection(for: review)
        self.deleter = deleter
    }

    /// Righe presentabili (keep vs removable).
    public var rows: [CategoryReviewRow] { review.rows }

    // MARK: - A-2 Selezione per-elemento

    /// Vero se l'id è selezionato per l'eliminazione.
    public func isSelected(_ id: String) -> Bool { selection.contains(id) }

    /// Inverte la selezione di un id **removable** (i keep sono protetti: no-op).
    public func toggleSelection(_ id: String) {
        guard review.removableIds.contains(id) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Seleziona tutti i removable.
    public func selectAllRemovable() { selection = Set(review.removableIds) }

    /// Deseleziona tutto.
    public func selectNone() { selection = [] }

    /// Id removable attualmente selezionati, in ordine stabile (ordine della review).
    public var selectedRemovableIds: [String] {
        review.removableIds.filter { selection.contains($0) }
    }

    /// Apre l'anteprima sull'insieme SELEZIONATO (mai i keep, mai vuoto): alimenta il
    /// percorso subset già esistente senza aggirare il gate (T-050).
    @discardableResult
    public func presentDeletionPreviewForSelection() -> Bool {
        presentDeletionPreview(of: selectedRemovableIds)
    }

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

    // MARK: - Gate d'anteprima a passi (per la UX reale)
    //
    // `requestDeletion` sopra attraversa il gate in un colpo solo (comodo per gli
    // oracoli). La schermata reale, invece, DEVE mostrare l'anteprima e attendere
    // l'assenso esplicito dell'utente: questi metodi espongono le transizioni del
    // `DeletionFlow` una alla volta, senza mai aggirarlo (T-050). Restano fedeli
    // agli stessi invarianti: solo id **removable** eleggibili, mai i keep; nessuna
    // anteprima vuota.

    /// Apre l'anteprima per gli id eleggibili (filtrati ai soli removable) e si
    /// ferma lì, in attesa dell'assenso. Restituisce `true` sse l'anteprima si è
    /// aperta su un insieme non vuoto (AC-113-2: selezione vuota ⇒ rifiutata).
    @discardableResult
    public func presentDeletionPreview(of ids: [String]) -> Bool {
        let removable = Set(review.removableIds)
        let eligible = ids.filter { removable.contains($0) }
        guard !eligible.isEmpty else { return false }
        return flow.presentPreview(for: eligible)
    }

    /// Comodità: apre l'anteprima per tutti i removable della proposta.
    @discardableResult
    public func presentDeletionPreviewForAllRemovable() -> Bool {
        presentDeletionPreview(of: review.removableIds)
    }

    /// L'utente conferma l'anteprima mostrata: accetta e passa a `confirmed`
    /// sull'insieme previewato. Consentito solo da un'anteprima aperta; l'insieme
    /// confermato coincide con quello previewato (mai i keep). Restituisce `true`
    /// sse è arrivato a `confirmed` (AC-113-1).
    @discardableResult
    public func confirmDeletion() -> Bool {
        guard flow.acceptPreview() else { return false }
        return flow.confirm()
    }

    /// FSE-J1 — Conferma il gate e ESEGUE l'eliminazione REALE (censimento C1: prima
    /// `confirmDeletion()` avanzava solo il gate e nessuna foto veniva eliminata). Passi:
    /// (1) autorizza il gate (preview→confirm); (2) invoca `deleter.delete(ids:)` sugli id
    /// selezionati (mai i keep); (3) su `success` toglie gli id dalla review e dalla
    /// selezione (le righe eliminate spariscono subito); su `cancelled`/`failed` la review
    /// resta invariata (mai un falso successo). Il gate è ripristinato in ogni caso.
    /// Restituisce l'esito PhotoKit reale così la View mostra un errore onesto su `failed`.
    @discardableResult
    public func confirmAndDelete() async -> BatchDeletionResult {
        guard confirmDeletion() else { return .cancelled }
        let ids = selectedRemovableIds
        guard !ids.isEmpty else {
            flow = DeletionFlow()
            return .cancelled
        }
        let result = await deleter.delete(ids: ids)
        if case .success = result {
            let removed = Set(ids)
            review = review.removing(ids: removed)
            selection.subtract(removed)
            for id in removed { assets[id] = nil }
        }
        flow = DeletionFlow() // consuma il gate: torna a rivedere (successo o meno)
        return result
    }

    /// L'utente annulla: azzera il gate e torna a rivedere (nessuna eliminazione).
    /// Il `DeletionFlow` è un value type, quindi si riparte da uno pulito.
    public func cancelDeletion() {
        flow = DeletionFlow()
    }
}
