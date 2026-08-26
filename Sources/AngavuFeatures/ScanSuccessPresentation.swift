import AngavuDomain

// E-3 (guscio UI, platform-puro) — Schermata di risultato: festa vs onesto.
//
// A esito terminale della scansione la Home mostra una schermata di risultato. La
// DECISIONE "quale esito → quale schermata" vive qui, nel layer PURO, come oracolo
// testabile; le animazioni (coriandoli) restano View-level, gated su Reduce Motion
// (equivalente statico), quindi compilate-ma-non-rese (L-COL-006).
//
// INVARIANTI DI ONESTÀ (manifesto):
//  • Niente festa su un mezzo successo: solo un successo VERO ad accesso PIENO
//    accende i coriandoli. Accesso limitato → ramo onesto (conteggio dichiarato
//    parziale, invito all'accesso completo). Fallimento → ramo onesto (motivo
//    esplicito, "Apri Impostazioni" se è un problema di permessi).
//  • Il conteggio mostrato è quello reale della scansione (`indexed`), mai gonfiato.

/// Modello di presentazione della schermata di risultato della scansione.
public struct ScanSuccessPresentation: Equatable, Sendable {
    /// Lo stile della schermata: festa (successo pieno) o onesto (parziale/errore).
    public enum Style: Equatable, Sendable {
        case celebration
        case honest
    }

    /// Lo stile risolto.
    public let style: Style
    /// Vero solo per la festa: i coriandoli sono riservati al successo pieno
    /// (la View li gata comunque su Reduce Motion, con equivalente statico).
    public let showsConfetti: Bool
    /// Titolo breve dell'esito.
    public let title: String
    /// Messaggio col conteggio reale (mai gonfiato); dichiara il parziale se tale.
    public let message: String
    /// Conteggio indicizzato reale, presente sugli esiti completati.
    public let indexedCount: Int?
    /// Vero quando il conteggio è PARZIALE (accesso limitato): dichiarato, mai totale.
    public let isPartialResult: Bool
    /// Etichetta dell'azione primaria ("È ora di fare pulizia!" / "Riprova").
    public let primaryActionTitle: String
    /// Vero quando l'azione primaria porta alla dashboard (numeri veri); falso
    /// quando invita a riprovare (fallimento).
    public let leadsToDashboard: Bool
    /// Vero quando l'esito è un problema di permessi: la UI offre "Apri Impostazioni".
    public let offersOpenSettings: Bool

    private init(
        style: Style,
        showsConfetti: Bool,
        title: String,
        message: String,
        indexedCount: Int? = nil,
        isPartialResult: Bool = false,
        primaryActionTitle: String,
        leadsToDashboard: Bool,
        offersOpenSettings: Bool = false
    ) {
        self.style = style
        self.showsConfetti = showsConfetti
        self.title = title
        self.message = message
        self.indexedCount = indexedCount
        self.isPartialResult = isPartialResult
        self.primaryActionTitle = primaryActionTitle
        self.leadsToDashboard = leadsToDashboard
        self.offersOpenSettings = offersOpenSettings
    }

    /// Deriva la schermata di risultato dallo stato di scansione, oppure `nil`
    /// quando lo stato NON è un esito terminale da mostrare come risultato
    /// (idle / richiesta permessi / analisi / annullata: quelli mostrano il flusso).
    public static func make(state: ScanState) -> ScanSuccessPresentation? {
        switch state {
        case .idle, .requestingPermission, .scanning, .cancelled:
            return nil
        case .completed(let indexed, let partial):
            return partial ? limited(indexed: indexed) : celebration(indexed: indexed)
        case .failed(let message):
            return failure(message: message)
        }
    }

    // MARK: - Rami

    /// Successo pieno: festa coi coriandoli e conteggio reale.
    private static func celebration(indexed: Int) -> ScanSuccessPresentation {
        .init(
            style: .celebration,
            showsConfetti: true,
            title: "Fatto!",
            message: "\(indexed) elementi analizzati, tutto sul tuo telefono. "
                + "Vediamo quanto puoi liberare.",
            indexedCount: indexed,
            primaryActionTitle: "È ora di fare pulizia!",
            leadsToDashboard: true
        )
    }

    /// Accesso limitato: nessuna festa, conteggio dichiarato parziale + invito.
    private static func limited(indexed: Int) -> ScanSuccessPresentation {
        .init(
            style: .honest,
            showsConfetti: false,
            title: "Analisi completata",
            message: "\(indexed) elementi analizzati — conteggio parziale (accesso limitato). "
                + "Consenti l'accesso completo per il quadro intero.",
            indexedCount: indexed,
            isPartialResult: true,
            primaryActionTitle: "Vedi i numeri veri",
            leadsToDashboard: true,
            offersOpenSettings: true
        )
    }

    /// Fallimento: ramo onesto, motivo esplicito, "Apri Impostazioni" se è permessi.
    private static func failure(message: String) -> ScanSuccessPresentation {
        .init(
            style: .honest,
            showsConfetti: false,
            title: "Analisi non riuscita",
            message: message,
            primaryActionTitle: "Riprova",
            leadsToDashboard: false,
            offersOpenSettings: message == ScanViewModel.accessDeniedMessage
        )
    }
}
