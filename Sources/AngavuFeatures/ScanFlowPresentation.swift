import AngavuDomain

// E-1 (guscio UI, platform-puro) — Flusso "Shazam" del primo avvio.
//
// La Home non ha più uno stato "idle" separato con un bottone da modulo: apre con
// UN SOLO tasto gigante centrale che, al tocco, chiede il permesso e avvia la
// scansione con UNA SOLA barra d'avanzamento. Questa struttura è la mappa PURA da
// `ScanState` alle decisioni osservabili del tasto e del carosello — l'ORACOLO
// testabile, così la resa SwiftUI (tasto animato, battito, riempimento) resta il
// solo strato "compilato-ma-non-testato" (L-COL-006).
//
// INVARIANTE DI ONESTÀ (manifesto: numeri veri): durante la fase di permesso il
// progresso è INDETERMINATO (`fill == nil`), mai una frazione fabbricata; solo la
// fase di analisi vera espone il riempimento reale (`AnalysisProgress.fraction`).

/// Modello di presentazione del flusso di scansione a tasto unico.
public struct ScanFlowPresentation: Equatable, Sendable {
    /// La fase visiva del flusso: instrada tasto, carosello e avanzamento.
    public enum Phase: Equatable, Sendable {
        /// Pronto (o dopo un annullamento): il tasto gigante invita al tocco.
        case ready
        /// Richiesta permessi: avanzamento INDETERMINATO (il tasto "batte").
        case preparing
        /// Analisi in corso: avanzamento DETERMINATO (il tasto si "riempie").
        case scanning
        /// Esito terminale (completata o fallita): la schermata di risultato
        /// (E-3) prende il posto del flusso; il tasto non è più il protagonista.
        case finished
    }

    /// La fase corrente.
    public let phase: Phase
    /// Vero solo quando il tasto è toccabile per (ri)avviare — mai durante il lavoro.
    public let isButtonEnabled: Bool
    /// Etichetta del tasto ("Analizza la libreria" / "Riprova").
    public let buttonTitle: String
    /// Sottotitolo sotto il tasto (invito o nota d'annullamento); `nil` durante il lavoro.
    public let buttonCaption: String?
    /// Vero mentre la metà superiore mostra il carosello "leggi mentre aspetti" (E-4).
    public let showsCarousel: Bool
    /// Vero quando l'avanzamento è INDETERMINATO (fase permesso → battito); falso
    /// quando è determinato (fase analisi → riempimento).
    public let isIndeterminate: Bool
    /// Livello di riempimento 0…1, presente SOLO in analisi determinata; `nil`
    /// durante il battito indeterminato (nessuna frazione fabbricata).
    public let fill: Double?
    /// Etichetta di stato sempre onesta durante il lavoro ("Chiedo l'accesso…" /
    /// "X di N"); `nil` a riposo o a esito terminale.
    public let statusLabel: String?
    /// Vero mentre l'analisi è interrompibile (stop cooperativo, motore T-004). La
    /// richiesta permessi non è annullabile in modo utile → falso.
    public let canCancel: Bool

    // Init privato coi default: ogni case di `init(state:)` specifica SOLO ciò che
    // differisce, così le combinazioni restano coerenti per costruzione.
    private init(
        phase: Phase,
        isButtonEnabled: Bool = false,
        buttonTitle: String = "Analizza la libreria",
        buttonCaption: String? = nil,
        showsCarousel: Bool = false,
        isIndeterminate: Bool = false,
        fill: Double? = nil,
        statusLabel: String? = nil,
        canCancel: Bool = false
    ) {
        self.phase = phase
        self.isButtonEnabled = isButtonEnabled
        self.buttonTitle = buttonTitle
        self.buttonCaption = buttonCaption
        self.showsCarousel = showsCarousel
        self.isIndeterminate = isIndeterminate
        self.fill = fill
        self.statusLabel = statusLabel
        self.canCancel = canCancel
    }

    /// Deriva il flusso dallo stato di scansione. Deterministica e totale: ogni
    /// `ScanState` ha una e una sola presentazione.
    public init(state: ScanState) {
        switch state {
        case .idle:
            self = .init(
                phase: .ready,
                isButtonEnabled: true,
                buttonTitle: "Analizza la libreria",
                buttonCaption: "Un tocco: numeri veri, tutto sul tuo dispositivo."
            )
        case .requestingPermission:
            self = .init(
                phase: .preparing,
                showsCarousel: true,
                isIndeterminate: true,
                statusLabel: "Chiedo l'accesso alla libreria…"
            )
        case .scanning(let progress):
            self = .init(
                phase: .scanning,
                showsCarousel: true,
                isIndeterminate: false,
                fill: progress.fraction,
                statusLabel: "\(progress.processed) di \(progress.total)",
                canCancel: true
            )
        case .completed:
            // Esito terminale: la schermata di risultato (E-3) guida da qui.
            self = .init(phase: .finished)
        case .cancelled(let progress):
            self = .init(
                phase: .ready,
                isButtonEnabled: true,
                buttonTitle: "Riprova",
                buttonCaption: "Analisi annullata a \(progress.processed) di \(progress.total). "
                    + "Niente è stato modificato."
            )
        case .failed:
            // Esito terminale: la schermata di risultato (E-3) mostra il ramo onesto.
            self = .init(phase: .finished)
        }
    }
}
