import AngavuDomain

// Guscio UI — Compressione video: presentazione PURA dello stato di compressione.
//
// Mappa `CompressionState` (T-116) nelle decisioni osservabili della schermata:
// fase corrente del flusso, titolo/dettaglio onesti, la stima del risparmio
// (SEMPRE marcata come stima), quale controllo è offerto (consenso opt-in →
// avvio → riprova), lo stato di lavorazione, e la nota della rete di sicurezza a
// compressione completata. Platform-puro (nessun import SwiftUI): è l'ORACOLO
// testabile della logica di presentazione, così la resa SwiftUI resta il solo
// strato «compilato-ma-non-testato» (L-COL-006).
//
// Invarianti di onestà, per costruzione: il risparmio è marcato stima (mai
// garantito); il consenso opt-in è offerto SOLO dopo la stima e prima dell'avvio
// (nessun avvio silenzioso); a `done` l'originale è instradato alla rete di
// sicurezza (recuperabile ~30 gg), mai perso.

/// Modello di presentazione della compressione, derivato dallo stato del view-model.
public struct CompressionPresentation: Equatable, Sendable {

    /// Fase del flusso di compressione dal punto di vista della schermata.
    public enum Phase: Equatable, Sendable {
        /// Nessuna stima ancora: si sceglie un video e si chiede la stima.
        case idle
        /// Stima del risparmio mostrata: si chiede il consenso opt-in esplicito.
        case estimated
        /// Consenso registrato: si può avviare la compressione (dietro anteprima).
        case consented
        /// Export o sostituzione in corso: progresso indeterminato, sorgente intatto.
        case working
        /// Completato: originale verso «Eliminati di recente», compresso pronto.
        case done
        /// Annullato (stop cooperativo): il video originale è intatto.
        case cancelled
        /// Fallito: motivo esplicito, con offerta di riprovare.
        case failed
    }

    /// La fase corrente.
    public let phase: Phase
    /// Titolo breve dello stato.
    public let title: String
    /// Dettaglio (sottotitolo / motivo d'errore).
    public let detail: String?
    /// Byte di risparmio STIMATO (mai esatto). Presente in `estimated`/`consented`.
    public let estimatedSavingBytes: Int64?
    /// Byte dell'output compresso reale. Presente solo in `done`.
    public let compressedOutputBytes: Int64?
    /// Offri il consenso opt-in: SOLO in fase `estimated` (mai un avvio silenzioso).
    public let offersConsent: Bool
    /// Offri l'avvio della compressione: SOLO in fase `consented`.
    public let offersCompression: Bool
    /// In lavorazione: la UI mostra progresso e permette l'annullamento cooperativo.
    public let isWorking: Bool
    /// Offri «Riprova»: SOLO in fase `failed`.
    public let offersRetry: Bool
    /// Nota della rete di sicurezza (originale recuperabile). Presente solo in `done`.
    public let safetyNote: String?

    private init(
        phase: Phase,
        title: String,
        detail: String? = nil,
        estimatedSavingBytes: Int64? = nil,
        compressedOutputBytes: Int64? = nil,
        offersConsent: Bool = false,
        offersCompression: Bool = false,
        isWorking: Bool = false,
        offersRetry: Bool = false,
        safetyNote: String? = nil
    ) {
        self.phase = phase
        self.title = title
        self.detail = detail
        self.estimatedSavingBytes = estimatedSavingBytes
        self.compressedOutputBytes = compressedOutputBytes
        self.offersConsent = offersConsent
        self.offersCompression = offersCompression
        self.isWorking = isWorking
        self.offersRetry = offersRetry
        self.safetyNote = safetyNote
    }

    /// Testo unico della rete di sicurezza (riusato dalla View), coerente con le
    /// altre schermate: l'originale finisce in «Eliminati di recente», recuperabile.
    public static let safetyNetText =
        "L'originale finisce in «Eliminati di recente» e resta recuperabile per "
        + "~30 giorni: la sostituzione avviene solo dopo la tua conferma."

    /// Deriva la presentazione dallo stato della compressione. Deterministica e
    /// totale: ogni `CompressionState` ha una e una sola presentazione. Le factory
    /// per-fase tengono questo dispatch corto (function_body_length) senza cambiare
    /// il comportamento.
    public init(state: CompressionState) {
        switch state {
        case .idle: self = Self.idlePresentation
        case .estimated(let saving): self = Self.estimatedPresentation(saving: saving)
        case .consented: self = Self.consentedPresentation
        case .exporting: self = Self.exportingPresentation
        case .replacing: self = Self.replacingPresentation
        case .done(let replacement): self = Self.donePresentation(replacement: replacement)
        case .cancelled: self = Self.cancelledPresentation
        case .failed(let reason): self = Self.failedPresentation(reason: reason)
        }
    }

    // MARK: Factory per-fase (comportamento identico, dispatch corto)

    private static let idlePresentation = CompressionPresentation(
        phase: .idle,
        title: "Comprimi video",
        detail: "Angavu stima quanto spazio libereresti ricodificando in HEVC, "
            + "tutto sul dispositivo. Scegli un video per la stima."
    )

    private static func estimatedPresentation(saving: ByteSize) -> CompressionPresentation {
        CompressionPresentation(
            phase: .estimated,
            title: "Risparmio stimato",
            detail: "È una stima: la compressione reale può variare. Nessuna "
                + "ricodifica parte senza il tuo consenso.",
            estimatedSavingBytes: saving.bytes,
            offersConsent: true
        )
    }

    private static let consentedPresentation = CompressionPresentation(
        phase: .consented,
        title: "Pronto a comprimere",
        detail: "Consenso registrato. Alla conferma dell'anteprima l'originale "
            + "sarà sostituito con la versione compressa.",
        offersCompression: true
    )

    private static let exportingPresentation = CompressionPresentation(
        phase: .working,
        title: "Compressione in corso…",
        detail: "Ricodifica HEVC sul dispositivo. Il video originale è intatto.",
        isWorking: true
    )

    private static let replacingPresentation = CompressionPresentation(
        phase: .working,
        title: "Sostituzione in corso…",
        detail: "Export riuscito: sto instradando l'originale alla rete di sicurezza.",
        isWorking: true
    )

    private static func donePresentation(replacement: CompressedReplacement) -> CompressionPresentation {
        CompressionPresentation(
            phase: .done,
            title: "Compressione completata",
            detail: "La versione compressa è pronta; l'originale è stato instradato "
                + "alla rete di sicurezza.",
            compressedOutputBytes: replacement.compressed.outputBytes,
            safetyNote: safetyNetText
        )
    }

    private static let cancelledPresentation = CompressionPresentation(
        phase: .cancelled,
        title: "Compressione annullata",
        detail: "Nessuna modifica: il video originale è intatto."
    )

    private static func failedPresentation(reason: String) -> CompressionPresentation {
        CompressionPresentation(
            phase: .failed,
            title: "Compressione non riuscita",
            detail: reason,
            offersRetry: true
        )
    }
}
