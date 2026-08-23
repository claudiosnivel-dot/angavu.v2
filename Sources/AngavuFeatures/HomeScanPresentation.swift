import AngavuDomain

// Guscio UI — Home + scansione: presentazione PURA dello stato di scansione.
//
// Mappa `ScanState` (T-111) nelle decisioni osservabili della Home: titolo/dettaglio
// onesti, quali controlli mostrare (avvia / annulla / apri Impostazioni), progresso,
// e la marcatura di conteggio parziale. Platform-puro (nessun import SwiftUI): è
// l'ORACOLO testabile della logica di presentazione, così la resa SwiftUI resta il
// solo strato "compilato-ma-non-testato" (L-COL-006). Nessun numero gonfiato: il
// conteggio parziale (accesso limited) è sempre dichiarato tale, mai spacciato per
// totale.

/// Modello di presentazione della Home, derivato dallo stato di scansione.
public struct HomeScanPresentation: Equatable, Sendable {
    /// La classe di stato che la Home sta mostrando: instrada i controlli.
    public enum Kind: Equatable, Sendable {
        /// Nessuna scansione ancora avviata (o resettata): pronto ad analizzare.
        case idle
        /// In corso: richiesta permessi o analisi. La UI mostra avanzamento.
        case working
        /// Completata: recap onesto coi numeri veri.
        case completed
        /// Annullata dall'utente: nulla è stato modificato.
        case cancelled
        /// Fallita: motivo esplicito, mai un blocco muto.
        case failed
    }

    /// La classe di stato corrente.
    public let kind: Kind
    /// Titolo breve dello stato (headline).
    public let title: String
    /// Dettaglio opzionale (sottotitolo / messaggio d'errore).
    public let detail: String?
    /// Progresso determinato, presente SOLO durante l'analisi vera e propria.
    /// `nil` durante la richiesta permessi (avanzamento indeterminato).
    public let progress: AnalysisProgress?
    /// Vero mentre l'analisi è interrompibile (stop cooperativo, motore T-004).
    /// La richiesta permessi non è annullabile in modo utile → falso.
    public let canCancel: Bool
    /// Vero quando l'utente può (ri)avviare una scansione col pulsante primario.
    public let showsPrimaryAction: Bool
    /// Etichetta del pulsante primario ("Analizza la libreria" / "Rianalizza" / "Riprova").
    public let primaryActionTitle: String
    /// Numero di elementi indicizzati, presente solo a scansione completata.
    public let indexedCount: Int?
    /// Vero quando il conteggio è PARZIALE (accesso limited): va dichiarato, mai
    /// spacciato per totale.
    public let isPartialResult: Bool
    /// Vero quando il fallimento è un accesso negato: la UI offre "Apri Impostazioni".
    public let offersOpenSettings: Bool

    // Init privato coi default: ogni case di `init(state:)` specifica SOLO ciò che
    // differisce, così le combinazioni restano coerenti per costruzione e la mappa
    // resta breve e leggibile.
    private init(
        kind: Kind,
        title: String,
        detail: String? = nil,
        progress: AnalysisProgress? = nil,
        canCancel: Bool = false,
        showsPrimaryAction: Bool = false,
        primaryActionTitle: String = "Analizza la libreria",
        indexedCount: Int? = nil,
        isPartialResult: Bool = false,
        offersOpenSettings: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
        self.canCancel = canCancel
        self.showsPrimaryAction = showsPrimaryAction
        self.primaryActionTitle = primaryActionTitle
        self.indexedCount = indexedCount
        self.isPartialResult = isPartialResult
        self.offersOpenSettings = offersOpenSettings
    }

    /// Deriva la presentazione dallo stato di scansione. Deterministica e totale:
    /// ogni `ScanState` ha una e una sola presentazione.
    public init(state: ScanState) {
        switch state {
        case .idle:
            self = .init(
                kind: .idle,
                title: "Pronto ad analizzare",
                detail: "Angavu conta i byte veri della tua libreria, tutto sul dispositivo.",
                showsPrimaryAction: true
            )
        case .requestingPermission:
            self = .init(kind: .working, title: "Richiedo l'accesso alla libreria…")
        case .scanning(let progress):
            self = .init(
                kind: .working,
                title: "Analisi in corso…",
                detail: "\(progress.processed) di \(progress.total)",
                progress: progress,
                canCancel: true
            )
        case .completed(let indexed, let partial):
            self = .init(
                kind: .completed,
                title: "Analisi completata",
                detail: Self.completedDetail(indexed: indexed, partial: partial),
                showsPrimaryAction: true,
                primaryActionTitle: "Rianalizza",
                indexedCount: indexed,
                isPartialResult: partial
            )
        case .cancelled(let progress):
            self = .init(
                kind: .cancelled,
                title: "Analisi annullata",
                detail: "Interrotta a \(progress.processed) di \(progress.total). Niente è stato modificato.",
                showsPrimaryAction: true,
                primaryActionTitle: "Riprova"
            )
        case .failed(let message):
            self = .init(
                kind: .failed,
                title: "Analisi non riuscita",
                detail: message,
                showsPrimaryAction: true,
                primaryActionTitle: "Riprova",
                offersOpenSettings: message == ScanViewModel.accessDeniedMessage
            )
        }
    }

    /// Recap onesto della scansione completata: il conteggio parziale (accesso
    /// limitato) è sempre marcato come tale, mai presentato come totale.
    private static func completedDetail(indexed: Int, partial: Bool) -> String {
        partial
            ? "\(indexed) elementi indicizzati — conteggio parziale (accesso limitato)."
            : "\(indexed) elementi indicizzati."
    }
}
