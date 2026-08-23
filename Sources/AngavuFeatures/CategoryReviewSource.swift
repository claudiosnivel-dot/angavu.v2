import AngavuDomain

// Guscio UI — Sorgente delle review di categoria: produce una `CategoryReview`
// REALE dai dati veri dell'indice, dietro i port dell'AppEnvironment.
//
// ONESTÀ (L-COL-006): qui si cabla SOLO la categoria che si può calcolare
// off-device senza soglie arbitrarie — gli **Screenshot**, un filtro puro sul
// sottotipo `.screenshot` già indicizzato (library_index, T-011). Le altre
// categorie del piano (duplicati esatti, foto simili, video grandi/vecchi, foto
// sfocate) richiedono hashing/Vision sul dispositivo o decisioni di soglia
// (grande/vecchio): NON sono qui, per non fabbricare numeri. Verranno cablate
// quando la loro sorgente reale sarà disponibile.
//
// Nessuna logica di dominio nuova: si riusano `ScreenshotCategory` (T-061),
// `BulkDeletionProposalComposer` (T-062) e la normalizzazione `CategoryReview`
// (T-113). Altitudine invariata: si legge dietro il port `AssetIndexReading`.

/// Categoria di pulizia presentabile in una schermata di review. Ogni caso porta
/// i propri testi (platform-puri, testabili) e sa produrre la propria review dai
/// dati veri quando questo è possibile off-device.
public enum CleanupCategory: String, CaseIterable, Sendable {
    /// Screenshot: eliminazione diretta, dal sottotipo indicizzato. Nessun keep.
    case screenshots

    /// Titolo della categoria.
    public var title: String {
        switch self {
        case .screenshots: return "Screenshot"
        }
    }

    /// Sottotitolo onesto: cosa contiene e come viene proposta.
    public var subtitle: String {
        switch self {
        case .screenshots:
            return "Le catture di schermo della tua libreria: eliminazione diretta, "
                + "nessuna «migliore» da tenere."
        }
    }

    /// SF Symbol della categoria (stringa: usata solo dalla View).
    public var symbol: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        }
    }
}

/// Produttore delle review reali dall'indice. `throws`: la lettura dell'indice non
/// va mai mascherata con un verde finto (un errore è uno stato d'errore esplicito
/// nella schermata, mai una lista vuota spacciata per «pulito»).
enum CategoryReviewSource {
    /// Compone la `CategoryReview` reale per la categoria data leggendo i dati veri
    /// dell'ambiente. Per gli screenshot: legge tutti gli asset indicizzati, filtra
    /// quelli col sottotipo `.screenshot`, ne compone una proposta in blocco (tutti
    /// removable, nessun keep) e la normalizza in `CategoryReview`.
    static func review(for category: CleanupCategory, from environment: AppEnvironment) throws -> CategoryReview {
        switch category {
        case .screenshots:
            let assets = try environment.indexReader.assets(matching: .all)
            let screenshots = ScreenshotCategory.screenshots(assets)
            let proposal = BulkDeletionProposalComposer.compose(from: screenshots)
            return .from(bulk: proposal)
        }
    }
}
