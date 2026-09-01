import AngavuDomain
import Foundation

// FSE-K3 — Commit dei risultati della scansione unificata nello store (fine scansione).
//
// Prima di K3 `HomeView.startScan()` faceva `store.invalidateAll()` CIECO all'avvio:
// svuotava memoria E persistenza (K1) prima ancora di sapere se la scansione sarebbe
// arrivata in fondo → un annullamento a metà cancellava i risultati validi della
// scansione precedente (e al lancio successivo si tornava al rilevatore al tap). Qui il
// commit avviene SOLO a scansione `completed`:
//   • ogni categoria RAGGIUNTA rimpiazza il valore precedente (write-through col token
//     catturato a INIZIO scansione, K2) e nasce `.fresh`;
//   • una categoria NON in `categoryResults` (rilevatore fallito) è INVALIDATA: il
//     vecchio valore non riflette il nuovo indice, si ricompone al tap — mai un
//     risultato vecchio spacciato per quello della nuova scansione;
//   • gli aggregati: `.dashboard` = i numeri calcolati dalla scansione (o invalidato se
//     le fasi dei numeri sono fallite), `.honestReport` invalidato (si ricalcola);
//   • `cancelled`/`failed`/altro: NESSUNA scrittura — memoria e persistenza della
//     scansione precedente restano intatte e valide.
// Logica pura sui parametri (oracolo: `RestoreHydrationTests`), chiamata dalla View.

enum ScanResultsCommit {
    /// Applica l'esito della scansione allo store. Restituisce `true` sse ha committato
    /// (stato `completed`).
    @discardableResult
    static func apply(
        state: ScanState,
        figures: DashboardScreen?,
        categoryResults: [CleanupCategory: CategoryReviewData],
        into store: AnalysisResultsStore,
        libraryToken: Data?,
        now: Date = Date()
    ) -> Bool {
        guard case .completed = state else { return false }
        if let figures {
            store.set(figures, for: .dashboard)
        } else {
            store.invalidate(.dashboard)
        }
        store.invalidate(.honestReport)
        for category in CleanupCategory.allCases {
            let key = AnalysisResultKey.category(category.rawValue)
            if let data = categoryResults[category] {
                store.set(data, for: key, at: now, libraryToken: libraryToken)
            } else {
                store.invalidate(key)
            }
        }
        return true
    }
}
