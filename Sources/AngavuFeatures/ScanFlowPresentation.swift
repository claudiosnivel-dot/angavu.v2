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
    /// la percentuale unificata della scansione, es. "45%"); `nil` a riposo o a
    /// esito terminale.
    ///
    /// FSE-I2 follow-up — durante l'analisi NON è più il conteggio grezzo per-fase
    /// "X di N": nella fase «foto simili» i `total` interni delle sotto-fasi saltano
    /// di proposito (composizione dHash = 2·N per l'headroom, keep-best = N+M) per la
    /// matematica della barra, così esposti come denominatore confondevano e potevano
    /// SUPERARE il conteggio foto reale (violazione di «numeri veri»). Ora l'etichetta
    /// è la percentuale della barra UNIFICATA (`ScanPipelineProgress.fraction`): una
    /// sola scala 0…100 %, monotòna non decrescente al confine di fase, mai oltre 100 %,
    /// mai un numero fabbricato. La fase resta nominata da `stageTitle`.
    public let statusLabel: String?
    /// Titolo della fase corrente della scansione unificata ("Indicizzo…" / "Calcolo
    /// i byte…" / "Spazio sul telefono…"); `nil` fuori dall'analisi. Rende visibile
    /// che l'unica barra copre più fasi del lavoro vero, senza fabbricare numeri.
    public let stageTitle: String?
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
        stageTitle: String? = nil,
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
        self.stageTitle = stageTitle
        self.canCancel = canCancel
    }

    /// Nome umano e onesto della fase, per la didascalia sotto il conteggio.
    /// FSE-F1 aggiunge le fasi dei rilevatori (imposte dal tipo `Stage`); i titoli e la
    /// copertura del carosello per l'intera attesa sono di FSE-F2 (che li testa).
    private static func phaseLabel(for stage: ScanPipelineProgress.Stage) -> String {
        switch stage {
        case .indexing: return "Indicizzo…"
        case .resolvingSizes: return "Calcolo i byte…"
        case .analyzingScreenshots: return "Cerco gli screenshot…"
        case .analyzingExactDuplicates: return "Cerco i duplicati…"
        case .analyzingSimilarPhotos: return "Confronto le foto simili…"
        case .analyzingBlurryPhotos: return "Controllo la nitidezza…"
        case .analyzingLargeOldVideos: return "Cerco i video grandi e vecchi…"
        }
    }

    /// Percentuale onesta della barra UNIFICATA (0…100 %) dalla frazione della
    /// pipeline. Clampata a [0, 1] per costruzione (la frazione è già in scala, ma il
    /// clamp rende l'invariante «mai oltre 100 %» un fatto locale, non un'assunzione) e
    /// arrotondata all'intero. Nessun denominatore grezzo: la scala è una sola per
    /// l'intera scansione, quindi stabile e monotòna al confine di fase.
    private static func percentLabel(for fraction: Double) -> String {
        let clamped = min(max(fraction, 0.0), 1.0)
        return "\(Int((clamped * 100).rounded()))%"
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
        case .scanning(let pipeline):
            // `fill` è la frazione UNIFICATA sull'intera pipeline (mai per-fase):
            // un'unica barra monotòna. `statusLabel` è la stessa frazione resa come
            // percentuale onesta (mai il conteggio grezzo per-fase, il cui denominatore
            // saltava/superava il conteggio foto nella fase simili); `stageTitle` nomina
            // la fase.
            self = .init(
                phase: .scanning,
                showsCarousel: true,
                isIndeterminate: false,
                fill: pipeline.fraction,
                statusLabel: Self.percentLabel(for: pipeline.fraction),
                stageTitle: Self.phaseLabel(for: pipeline.stage),
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
