import Foundation

// Macrotask `blurry_photos` — modello di dominio PURO delle foto sfocate.
//
// Due pezzi, uno per task atomico, tutti senza alcun tipo di piattaforma
// (altitudine `domain ↛ data`, 00-INDEX §1bis):
//   • T-070 port `SharpnessScoring` + soglia di sfocatura e classificazione blurry;
//   • T-071 aesthetics come progressive enhancement iOS 18 (`BlurScore`/`BlurAssessment`).
//
// Come `similar_photos`, il Domain NON importa Core Image/Vision: il punteggio di
// nitidezza e l'aesthetics score vivono dietro port implementati nel Data layer; qui
// arrivano solo valori puri (`Double?`). La classificazione è un **suggerimento**:
// nessuna eliminazione qui — la proposta passa dal gate anteprima di `safety_net` (T-050).

// MARK: - T-070 — Punteggio di nitidezza dietro adapter e soglia di sfocatura

/// Port del punteggio di nitidezza (architettura esagonale, come `QualityScoring`).
/// L'implementazione reale (Core Image/vImage: varianza del Laplaciano) vive nel
/// Data layer; il Domain riceve SOLO un `Double?` di nitidezza normalizzata.
///
/// Sincrono e agnostico, come gli altri port: il chiamante lo mette off-main.
public protocol SharpnessScoring {
    /// Nitidezza normalizzata 0…1 (più alto = più nitido), oppure `nil` se non
    /// calcolabile on-device (originale solo in iCloud, decodifica fallita). Un asset
    /// di cui non si può misurare la nitidezza non viene mai dichiarato sfocato
    /// (T-070): mai un falso positivo su un asset non verificabile.
    func sharpness(for asset: LibraryAsset) throws -> Double?
}

/// Soglia di sfocatura: sotto la soglia un asset è considerato `blurry`. La nitidezza
/// e la soglia vivono sulla stessa scala normalizzata 0…1 del port `SharpnessScoring`.
///
/// FSE-C2 — La nitidezza (varianza del Laplaciano, `SharpnessMetric`) è SENSIBILE ALLA
/// RISOLUZIONE di decodifica: la stessa foto letta a 64px o a piena risoluzione dà
/// valori grezzi diversi. Perciò la soglia dichiara la taglia a cui è tarata
/// (`referenceLongestSide`, la taglia logica `.sharpness` ≈64px di FSE-C1): un numero di
/// nitidezza senza la sua risoluzione di riferimento è privo di significato. Cambiando
/// la taglia di decodifica, la soglia va RI-TARATA e ri-dichiarata, mai ereditata a caso.
public struct BlurThreshold: Equatable, Sendable {
    /// Nitidezza minima (esclusa) per NON essere sfocato. Confinata a 0…1.
    public let minimumSharpness: Double

    /// Lato lungo (px) dell'immagine decodificata a cui questa soglia è tarata. È
    /// metadato DICHIARATIVO (non entra nella classificazione): documenta la scala su
    /// cui `minimumSharpness` è calibrata, così un cambio di taglia è visibile e la
    /// ri-taratura è forzata. Default 64: la taglia `.sharpness` di FSE-C1.
    public let referenceLongestSide: Int

    public init(minimumSharpness: Double, referenceLongestSide: Int = 64) {
        self.minimumSharpness = min(1, max(0, minimumSharpness))
        self.referenceLongestSide = max(1, referenceLongestSide)
    }
}

/// Classificazione pura sfocato/non-sfocato per soglia.
public enum BlurClassification {
    /// Regola di confine **dichiarata e deterministica** (AC-070-2): un asset è
    /// `blurry` se e solo se la sua nitidezza è **strettamente sotto** la soglia.
    /// Esattamente ALLA soglia → **non** sfocato (abbastanza nitido): scelta
    /// conservativa, nessun falso positivo al confine, coerente col manifesto
    /// "suggerimento, mai eliminazione in autonomia". Nitidezza `nil` (non
    /// calcolabile on-device) → **non** sfocato: mai flaggato ciò che non si misura.
    public static func isBlurry(sharpness: Double?, threshold: BlurThreshold) -> Bool {
        guard let sharpness else { return false }
        return sharpness < threshold.minimumSharpness
    }

    /// Classifica un singolo asset interrogando il port di nitidezza.
    public static func isBlurry(
        _ asset: LibraryAsset,
        scoring: SharpnessScoring,
        threshold: BlurThreshold
    ) throws -> Bool {
        try isBlurry(sharpness: scoring.sharpness(for: asset), threshold: threshold)
    }

    /// Seleziona gli asset **sfocati** fra i candidati, a blocchi cancellabili
    /// (motore T-004): la cancellazione al confine di un blocco lascia i candidati
    /// residui non processati e l'esito porta con sé il progresso raggiunto.
    ///
    /// La sfocatura ha senso solo per le **foto**: i video sono esclusi a monte
    /// (una "nitidezza fotografica" del video non è definita qui). L'ordine dei
    /// blurry rispetta l'ordine d'ingresso dei candidati (deterministico).
    public static func blurry(
        among assets: [LibraryAsset],
        scoring: SharpnessScoring,
        threshold: BlurThreshold,
        chunkSize: Int = 64,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<[LibraryAsset]> {
        let photos = assets.filter { $0.kind == .photo }
        let engine = ChunkedAnalysis<LibraryAsset, [LibraryAsset]>(
            chunkSize: chunkSize,
            initial: []
        ) { blurry, asset in
            var next = blurry
            if try isBlurry(asset, scoring: scoring, threshold: threshold) {
                next.append(asset)
            }
            return next
        }
        return engine.run(over: photos, cancellation: cancellation, progress: progress)
    }
}

// MARK: - T-071 — Aesthetics score come progressive enhancement iOS 18

/// Port dell'aesthetics/utility score (esagonale), **progressive enhancement** iOS 18.
/// L'implementazione reale (`VNCalculateImageAestheticsScoresRequest`) vive nel Data
/// layer; il Domain riceve `nil` dove non disponibile (iOS 17, o non calcolabile
/// on-device). Mai un requisito minimo: la sua assenza non fa mai fallire nulla.
public protocol AestheticsScoring {
    /// Aesthetics score dell'asset (0…1), o `nil` dove non disponibile.
    func aesthetics(for asset: LibraryAsset) throws -> Double?
}

/// Punteggio di sfocatura arricchito: nitidezza (T-070) + aesthetics opzionale
/// (solo iOS 18). Il termine aesthetics è **progressive enhancement**: su iOS 17 è
/// `nil`, l'assessment è marcato esplicitamente `usesAesthetics == false` e il
/// calcolo non fallisce (AC-071-2). Più alto = qualità migliore (meno sfocato).
public struct BlurScore: Equatable, Sendable {
    /// Nitidezza normalizzata 0…1 (sempre presente in un assessment prodotto).
    public let sharpness: Double
    /// Aesthetics score (solo iOS 18); `nil` = degradato a sola nitidezza. Mai un requisito.
    public let aesthetics: Double?

    public init(sharpness: Double, aesthetics: Double?) {
        self.sharpness = sharpness
        self.aesthetics = aesthetics
    }

    /// Vero se il termine aesthetics ha concorso al punteggio (iOS 18). Falso =
    /// degradato alla sola nitidezza: marcatura esplicita "senza aesthetics" (AC-071-2).
    public var usesAesthetics: Bool { aesthetics != nil }

    /// Punteggio combinato: somma dei soli termini **disponibili**. Su iOS 18 include
    /// il termine aesthetics oltre alla nitidezza (AC-071-1); su iOS 17 è la sola
    /// nitidezza (AC-071-2). L'assenza del termine estetico non concorre né fa fallire.
    public var combined: Double {
        sharpness + (aesthetics ?? 0)
    }
}

/// Composizione pura del punteggio di sfocatura arricchito.
public enum BlurAssessment {
    /// Costruisce un `BlurScore` da valori puri già misurati. Se `aesthetics` è `nil`
    /// (iOS 17), l'assessment resta valido ed è marcato "senza aesthetics" (AC-071-2);
    /// se è presente, il termine concorre al combinato (AC-071-1).
    public static func score(sharpness: Double, aesthetics: Double?) -> BlurScore {
        BlurScore(sharpness: sharpness, aesthetics: aesthetics)
    }

    /// Valuta un asset combinando nitidezza (T-070) e aesthetics (iOS 18) dai rispettivi
    /// port. Su iOS 18 l'aesthetics concorre (AC-071-1); su iOS 17 il provider
    /// restituisce `nil` e l'assessment degrada alla sola nitidezza, marcato come tale
    /// (AC-071-2), senza fallire. Restituisce `nil` solo se la nitidezza stessa non è
    /// calcolabile on-device: senza nitidezza non c'è assessment (coerente con T-070).
    public static func assess(
        _ asset: LibraryAsset,
        sharpnessScoring: SharpnessScoring,
        aestheticsScoring: AestheticsScoring
    ) throws -> BlurScore? {
        guard let sharpness = try sharpnessScoring.sharpness(for: asset) else { return nil }
        let aesthetics = try aestheticsScoring.aesthetics(for: asset)
        return BlurScore(sharpness: sharpness, aesthetics: aesthetics)
    }
}
