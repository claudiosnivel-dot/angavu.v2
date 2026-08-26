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
    public enum Stage: Int, Equatable, Sendable, CaseIterable {
        /// Enumerazione + mapping + scrittura dell'indice.
        case indexing
        /// Risoluzione dei byte reali per-asset + aggregazione per categoria.
        case resolvingSizes
        /// Misura della residenza per-asset (spazio device liberabile ORA, P0-2b).
        case measuringDeviceSpace
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
