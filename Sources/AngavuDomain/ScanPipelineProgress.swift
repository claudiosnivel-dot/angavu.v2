import Foundation

// Progresso UNIFICATO della scansione primo-avvio ("Shazam"), cuore PURO.
//
// Difetto emerso al device-test (POST-DEVICE, flusso E): il tasto gigante mostrava
// una barra che copriva SOLO l'indicizzazione; il grosso del lavoro vero (risoluzione
// dei byte per-asset e misura dello spazio device) avveniva DOPO, in un'altra
// schermata, dietro uno spinner indeterminato «Calcolo dei numeri veri…». La barra
// non era «unificata con la vera scansione». Questo tipo modella un'unica barra
// monotòna che attraversa tutte le fasi del lavoro, così la resa (il tasto che si
// riempie) resta l'unico strato compilato-ma-non-reso (L-COL-006).
//
// Invariante di onestà (manifesto: numeri veri): la frazione complessiva non è mai
// fabbricata — è composta dalle frazioni REALI per-fase; è monotòna non decrescente
// nel passaggio da una fase alla successiva (la fase che completa e quella che inizia
// coincidono al confine).

/// Progresso di una scansione a più fasi, per una barra unica.
public struct ScanPipelineProgress: Equatable, Sendable {
    /// Le fasi del lavoro vero, in ordine. Il `rawValue` è l'indice della fase e
    /// pesa la frazione complessiva (fasi equipesate: ognuna copre una quota uguale
    /// della barra). Ordine = ordine di esecuzione.
    ///
    /// FSE-F1 — «un'unica scansione fa tutto»: alle due fasi dei numeri veri
    /// (indice → byte) seguono le cinque fasi dei RILEVATORI di categoria, così le
    /// categorie si calcolano nella stessa passata e aprire una categoria è istantaneo
    /// (dalla cache), mai una nuova scansione al tap.
    ///
    /// FSE-G1 (strategia B) — la MISURA della residenza device è uscita dalla barra:
    /// è I/O pesante su ogni originale (FAST-SCAN-ENGINE-PLAN §1.7) e non serve ai
    /// numeri di libreria/categoria, solo alla cifra «liberabile sul telefono ORA».
    /// Ora atterra col caveat e si completa in background (`DashboardViewModel.measureResidency`),
    /// fuori dal percorso obbligatorio. Restano SETTE fasi, **equipesate** — la pesatura
    /// è DICHIARATA: ognuna copre 1/7 della barra. È la scelta onesta e semplice: non
    /// fabbrica mai una frazione; i rilevatori pesanti (duplicati/simili/sfocate)
    /// impiegano più tempo REALE entro la loro quota, invece di gonfiare il loro peso.
    public enum Stage: Int, Equatable, Sendable, CaseIterable {
        /// Enumerazione + mapping + scrittura dell'indice.
        case indexing
        /// Risoluzione dei byte reali per-asset + aggregazione per categoria.
        case resolvingSizes
        /// Rilevatore screenshot (filtro puro sul sottotipo indicizzato).
        case analyzingScreenshots
        /// Rilevatore duplicati esatti (SHA-256 sui candidati per dimensione).
        case analyzingExactDuplicates
        /// Rilevatore foto simili (distanza semantica Vision, «tieni la migliore»).
        case analyzingSimilarPhotos
        /// Rilevatore foto sfocate (nitidezza sotto soglia).
        case analyzingBlurryPhotos
        /// Rilevatore video grandi e vecchi (soglie congiunte, filtro puro).
        case analyzingLargeOldVideos
    }

    /// La fase corrente.
    public let stage: Stage
    /// Progresso REALE entro la fase corrente (mai fabbricato).
    public let stageProgress: AnalysisProgress

    public init(stage: Stage, stageProgress: AnalysisProgress) {
        self.stage = stage
        self.stageProgress = stageProgress
    }

    /// Frazione complessiva 0…1 sull'intera pipeline: le fasi sono equipesate e la
    /// frazione entro la fase corrente riempie la sua quota. Monotòna al confine:
    /// fine di una fase (`stageProgress.fraction == 1`) e inizio della successiva
    /// (`fraction == 0`) danno lo stesso valore complessivo, quindi la barra non
    /// arretra mai passando di fase.
    public var fraction: Double {
        let stageCount = Double(Stage.allCases.count)
        guard stageCount > 0 else { return 1.0 }
        return (Double(stage.rawValue) + stageProgress.fraction) / stageCount
    }
}
