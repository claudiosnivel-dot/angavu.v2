import Foundation
import AngavuDomain

// Guscio UI — Sorgente delle review di categoria: produce una `CategoryReview`
// REALE dai dati veri dell'indice, dietro i port dell'AppEnvironment.
//
// C-1 (POST-DEVICE) — Cablate le categorie del cuore-foto oltre agli Screenshot:
// **duplicati esatti** (T-030/31/32), **foto simili** (T-040…43), **foto sfocate**
// (T-070/71) e **video grandi/vecchi** (T-060/62). Il motore di dominio è già verde:
// qui si aggancia soltanto — nessuna logica di dominio nuova. I rilevatori pesanti
// (hashing SHA-256, feature print Vision, nitidezza Core Image) vivono dietro i port
// dell'AppEnvironment (`contentHasher`/`featurePrinter`/`qualityScorer`/
// `sharpnessScorer`), così questa mappa categoria→sorgente è testabile con dei fake
// senza device (oracolo puro). Gli adapter reali restano compilati-non-testati sul
// device (L-COL-006).
//
// ONESTÀ: la selezione "tieni la migliore" è protetta per costruzione — duplicati e
// simili mettono il keep nei `keepIds`, mai fra i removable, e la preselezione
// (`CategorySelectionPolicy`) è `Set(removableIds)`. Ogni eliminazione passa sempre
// dal gate d'anteprima obbligatorio della rete di sicurezza (`DeletionFlow`, T-050):
// qui si compone solo la proposta, mai si elimina.
//
// Altitudine invariata: si legge dietro i port del Data; il Domain resta puro.

/// Categoria di pulizia presentabile in una schermata di review. Ogni caso porta i
/// propri testi (platform-puri, testabili) e sa produrre la propria review dai dati
/// veri dietro i port dell'AppEnvironment.
public enum CleanupCategory: String, CaseIterable, Sendable {
    /// Screenshot: eliminazione diretta, dal sottotipo indicizzato. Nessun keep.
    case screenshots
    /// Duplicati esatti (byte identici): SHA-256 sui candidati per dimensione, si
    /// tiene una copia, il resto è eliminabile.
    case exactDuplicates
    /// Foto simili: cluster per distanza semantica (Vision), si tiene la migliore.
    case similarPhotos
    /// Foto sfocate: nitidezza sotto soglia, eliminazione diretta (nessun keep).
    case blurryPhotos
    /// Video grandi e vecchi: oltre le soglie congiunte, eliminazione diretta.
    case largeOldVideos

    /// Titolo della categoria.
    public var title: String {
        switch self {
        case .screenshots: return "Screenshot"
        case .exactDuplicates: return "Duplicati esatti"
        case .similarPhotos: return "Foto simili"
        case .blurryPhotos: return "Foto sfocate"
        case .largeOldVideos: return "Video grandi e vecchi"
        }
    }

    /// Sottotitolo onesto: cosa contiene e come viene proposta. Dichiara le soglie e
    /// le euristiche invece di nasconderle (manifesto: numeri veri, coi caveat).
    public var subtitle: String {
        switch self {
        case .screenshots:
            return "Le catture di schermo della tua libreria: eliminazione diretta, "
                + "nessuna «migliore» da tenere."
        case .exactDuplicates:
            return "Copie identiche byte-per-byte (verificate con SHA-256): si tiene "
                + "una copia, le altre sono eliminabili. Solo ciò che è leggibile sul "
                + "telefono — un originale in iCloud non viene mai dichiarato duplicato."
        case .similarPhotos:
            return "Scatti quasi uguali, raggruppati per somiglianza: si propone di "
                + "tenere il migliore del gruppo. È una stima di somiglianza, non una "
                + "certezza: rivedi prima di eliminare."
        case .blurryPhotos:
            return "Foto con nitidezza sotto soglia. È un suggerimento: ciò che non è "
                + "misurabile sul telefono non viene mai segnato come sfocato."
        case .largeOldVideos:
            return "Video oltre 100 MB e più vecchi di un anno, dal più grande. "
                + "Eliminazione diretta: nessuna «migliore» da tenere."
        }
    }

    /// SF Symbol della categoria (stringa: usata solo dalla View).
    public var symbol: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .exactDuplicates: return "square.on.square"
        case .similarPhotos: return "photo.stack"
        case .blurryPhotos: return "camera.filters"
        case .largeOldVideos: return "film.stack"
        }
    }

    /// FSE-F1 — fase della barra unificata in cui questa categoria viene calcolata
    /// durante la scansione «un'unica scansione fa tutto». L'ordine dei `case` di
    /// `CleanupCategory` (screenshot → duplicati → simili → sfocate → grandi/vecchi)
    /// coincide con l'ordine delle fasi rilevatore in `ScanPipelineProgress.Stage`.
    var scanStage: ScanPipelineProgress.Stage {
        switch self {
        case .screenshots: return .analyzingScreenshots
        case .exactDuplicates: return .analyzingExactDuplicates
        case .similarPhotos: return .analyzingSimilarPhotos
        case .blurryPhotos: return .analyzingBlurryPhotos
        case .largeOldVideos: return .analyzingLargeOldVideos
        }
    }

    /// Se questa categoria è calcolata EAGER dentro la scansione unificata, o DIFFERITA
    /// al primo tap. Knob della policy (mantenuto per poter differire di nuovo se serve).
    ///
    /// Storia: dopo il device-test i rilevatori per-foto pesanti — foto **simili** e
    /// **sfocate** — furono DIFFERITI perché il clustering greedy sul feature print
    /// Vision era O(N²) confronti + O(N) osservazioni Vision trattenute → **jetsam**
    /// (crash osservato, fase «Cerco i duplicati…» → simili).
    ///
    /// **FSE-H** ha reso quel percorso a MEMORIA LIMITATA: burst nativi (gratis) → dHash
    /// 64-bit (`UInt64` per foto) → BK-tree O(N·log N) (`clustersByHash`, nessuna immagine
    /// trattenuta) → feature print Vision demoto a conferma opzionale; `autoreleasepool`
    /// per foto (FSE-H3). Le sfocate calcolano una nitidezza per foto (memoria O(1), pool
    /// per foto). Ora reggono la scansione eager sull'intera libreria: **tutte le
    /// categorie sono EAGER** → aprirne una è istantaneo dalla cache (obiettivo FSE-F1
    /// ripristinato per tutte). Il guadagno/limite reale resta device-only (§7).
    var runsInUnifiedScan: Bool {
        switch self {
        case .screenshots, .exactDuplicates, .largeOldVideos, .similarPhotos, .blurryPhotos:
            return true
        }
    }
}

/// Soglie e parametri **dichiarati** dei rilevatori di categoria. Sono default
/// conservativi (decisione utente 2026-08-26: grandi/vecchi = ≥100 MB e >1 anno);
/// renderli regolabili dall'utente (slider) è una fase successiva pianificata.
enum CategoryDetectionDefaults {
    /// "Grande" per i video: ≥ 100 MB.
    static let largeVideoMinBytes: Int64 = 100 * 1024 * 1024
    /// "Vecchio" per i video: creato più di 365 giorni fa.
    static let largeVideoMaxAgeDays: Double = 365
    /// Soglie di similarità (scale separate: semantica Vision vs Hamming del dHash).
    /// Valori dichiarati e conservativi, affinabili in seguito.
    static let similarity = SimilarityThresholds(semantic: 0.5, hamming: 10)
    /// Soglia di sfocatura: nitidezza normalizzata 0…1, sfocato se strettamente sotto.
    /// FSE-C2 — taglia di riferimento DICHIARATA = `.sharpness` (≈64px, FSE-C1): il
    /// valore 0.3 è tarato a questa scala (48×48 dopo il ricampionamento). C1 non ha
    /// cambiato la risoluzione effettiva del kernel (il percorso legacy ricampionava già
    /// a ≈64px), quindi 0.3 resta valido; qui la scala è resa esplicita e vincolata,
    /// non più assunta. Ri-tarabile se la taglia `.sharpness` cambia (BlurThreshold).
    static let blur = BlurThreshold(
        minimumSharpness: 0.3,
        referenceLongestSide: LogicalImageSize.sharpness.longestSide
    )
    /// Blocco d'analisi cancellabile (motore T-004).
    static let chunkSize = 64
}

/// Review reale + i metadati per-id degli asset coinvolti (A-3), per etichette umane
/// e miniature. `assets` mappa id→`LibraryAsset` per keep e removable della review.
struct CategoryReviewData {
    let review: CategoryReview
    let assets: [String: LibraryAsset]
}

/// FSE-J2 — Potatura chirurgica: dopo un'eliminazione reale, togliere gli id eliminati
/// dalla review E dai metadati per-id, così una categoria in cache resta valida senza
/// far ripartire il rilevatore. `AnalysisResultsStore.pruneDeleted` la usa via il
/// protocollo su ogni entry `.category(...)`.
extension CategoryReviewData: IdentifierPrunable {
    func removing(ids: Set<String>) -> CategoryReviewData {
        guard !ids.isEmpty else { return self }
        return CategoryReviewData(
            review: review.removing(ids: ids),
            assets: assets.filter { !ids.contains($0.key) }
        )
    }
}

/// Produttore delle review reali dall'indice. `throws`: la lettura dell'indice o il
/// fallimento di un rilevatore non vanno mai mascherati con un verde finto (un errore
/// è uno stato d'errore esplicito nella schermata, mai una lista vuota spacciata per
/// «pulito»).
enum CategoryReviewSource {
    /// Compone la review reale + i metadati degli asset per la categoria, dietro i
    /// port dell'ambiente.
    ///
    /// - Parameter progress: callback d'avanzamento (X/N) per le categorie che girano
    ///   il motore a blocchi (duplicati/simili/sfocate). Le categorie a filtro puro
    ///   (screenshot, grandi/vecchi) non lo invocano: sono immediate e restano
    ///   onestamente indeterminate. Default no-op (usato dall'oracolo).
    /// - Parameter cancellation: token cooperativo. FSE-F1: la scansione unificata
    ///   passa il PROPRIO token così i rilevatori pesanti (duplicati/simili/sfocate)
    ///   si fermano quando l'utente annulla la scansione; una categoria interrotta
    ///   lancia (via `completed(_:)`) e la scansione la lascia non-cachata (mai un
    ///   risultato parziale spacciato per completo). Default: token nuovo (le aperture
    ///   singole di categoria restano indipendenti).
    static func reviewData(
        for category: CleanupCategory,
        from environment: AppEnvironment,
        cancellation: CancellationToken = CancellationToken(),
        progress: (AnalysisProgress) -> Void = { _ in }
    ) throws -> CategoryReviewData {
        switch category {
        case .screenshots:
            return try screenshotsReview(from: environment)
        case .exactDuplicates:
            return try exactDuplicatesReview(from: environment, cancellation: cancellation, progress: progress)
        case .similarPhotos:
            return try similarPhotosReview(from: environment, cancellation: cancellation, progress: progress)
        case .blurryPhotos:
            return try blurryPhotosReview(from: environment, cancellation: cancellation, progress: progress)
        case .largeOldVideos:
            return try largeOldVideosReview(from: environment)
        }
    }

    /// Comodità (retro-compatibile): la sola `CategoryReview`, senza metadati.
    static func review(for category: CleanupCategory, from environment: AppEnvironment) throws -> CategoryReview {
        try reviewData(for: category, from: environment).review
    }

    // MARK: - Screenshot (filtro puro sul sottotipo indicizzato)

    private static func screenshotsReview(from environment: AppEnvironment) throws -> CategoryReviewData {
        let assets = try environment.indexReader.assets(matching: .all)
        let screenshots = ScreenshotCategory.screenshots(assets)
        let proposal = BulkDeletionProposalComposer.compose(from: screenshots)
        let review = CategoryReview.from(bulk: proposal)
        return CategoryReviewData(review: review, assets: indexed(screenshots))
    }

    // MARK: - Duplicati esatti (SHA-256 sui candidati per dimensione)

    private static func exactDuplicatesReview(
        from environment: AppEnvironment,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) throws -> CategoryReviewData {
        let sized = try sizedAssets(from: environment)
        let groups = SizeCandidateGrouping.candidateGroups(sized)
        let clusters = try completed(ExactDuplicateClustering.clusters(
            from: groups,
            hasher: environment.contentHasher,
            chunkSize: CategoryDetectionDefaults.chunkSize,
            cancellation: cancellation,
            progress: progress
        ))
        let proposals = KeepOneSelection.proposals(for: clusters)
        let review = CategoryReview(
            keepIds: proposals.map(\.keep.asset.id),
            removableIds: proposals.flatMap { $0.removable.map(\.asset.id) }
        )
        let involved = proposals.flatMap { [$0.keep] + $0.removable }.map(\.asset)
        return CategoryReviewData(review: review, assets: indexed(involved))
    }

    // MARK: - Foto simili (cluster per distanza semantica, "tieni la migliore")

    private static func similarPhotosReview(
        from environment: AppEnvironment,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) throws -> CategoryReviewData {
        let photos = try environment.indexReader.assets(matching: .all).filter { $0.kind == .photo }
        let photoCount = photos.count
        // FSE-I2 — La fase «simili» ha DUE sotto-fasi costose per-foto: la composizione
        // dHash (una decodifica piccola per foto) e il keep-best (il quality scorer per
        // membro di cluster). Prima FSE-I2 solo la composizione riportava progresso, così
        // la barra toccava N/N e RESTAVA FERMA per tutto il keep-best (il ~1 min osservato
        // al 2° device-test). Ora un'unica frazione monotòna copre entrambe:
        //   • composizione → [0, 0.5): totale `2·N` (headroom per il keep-best, i cui
        //     membri sono al più N — ogni candidato sta in un solo cluster); ogni unità è
        //     una foto realmente composta, mai una frazione fabbricata;
        //   • keep-best   → [~0.5, 1.0]: totale `N + M` (M = membri dei cluster reali,
        //     M ≤ N), `processed = N + membri scorati`. Al confine N/(N+M) ≥ 0.5 (M ≤ N):
        //     monotòna non decrescente; raggiunge 1.0 quando l'ultimo membro è scorato.
        // FSE-H2 — Percorso PRINCIPALE: il dHash percettivo REALE (miniatura C1), cablato
        // dietro il port. Trattiene solo un `UInt64` per candidato (memoria O(1) per foto),
        // mai un feature print Vision. Un asset senza dHash resta `nil` → singleton.
        let compositionTotal = 2 * photoCount
        let candidates = try completed(SimilarCandidateComposition.candidates(
            for: photos,
            hashing: environment.perceptualHasher,
            analysis: .serial(chunkSize: CategoryDetectionDefaults.chunkSize),
            cancellation: cancellation,
            progress: { local in
                progress(AnalysisProgress(processed: local.processed, total: compositionTotal))
            }
        ))
        // Clustering a MEMORIA LIMITATA per vicinanza dHash (BK-tree, FSE-H1): O(N·log N)
        // senza trattenere immagini. Il feature print Vision è demoto a conferma opzionale
        // delle coppie borderline (mai il percorso principale) — non gira qui, così sparisce
        // la ritenzione O(N) di osservazioni Vision che causava il jetsam.
        let allClusters = SimilarClustering.clustersByHash(
            of: candidates,
            maxHammingDistance: CategoryDetectionDefaults.similarity.hamming
        )
        // Solo i gruppi REALI di simili (≥ 2): un singleton non ha nulla da proporre e
        // non deve comparire come "da tenere" (eviterebbe di elencare tutta la libreria).
        let realClusters = allClusters.filter { $0.members.count > 1 }
        let keepBestMembers = realClusters.reduce(0) { $0 + $1.members.count }
        let keepBestTotal = photoCount + keepBestMembers
        // FSE-I2 — il keep-best continua la stessa barra: dai N già "spesi" dalla
        // composizione (headroom) fino a N+M. La barra si muove per tutto lo scoring.
        let proposals = try SimilarDeletionProposal.proposals(
            for: realClusters,
            scoring: environment.qualityScorer,
            progress: { local in
                progress(AnalysisProgress(processed: photoCount + local.processed, total: keepBestTotal))
            }
        )
        let review = CategoryReview(
            keepIds: proposals.map(\.keep.asset.id),
            removableIds: proposals.flatMap { $0.removable.map(\.asset.id) }
        )
        let involved = proposals.flatMap { [$0.keep] + $0.removable }.map(\.asset)
        return CategoryReviewData(review: review, assets: indexed(involved))
    }

    // MARK: - Foto sfocate (nitidezza sotto soglia)

    private static func blurryPhotosReview(
        from environment: AppEnvironment,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void
    ) throws -> CategoryReviewData {
        let assets = try environment.indexReader.assets(matching: .all)
        let blurry = try completed(BlurClassification.blurry(
            among: assets,
            scoring: environment.sharpnessScorer,
            threshold: CategoryDetectionDefaults.blur,
            chunkSize: CategoryDetectionDefaults.chunkSize,
            cancellation: cancellation,
            progress: progress
        ))
        return CategoryReviewData(review: CategoryReview.fromBlurry(blurry), assets: indexed(blurry))
    }

    // MARK: - Video grandi e vecchi (filtro puro per soglie congiunte)

    private static func largeOldVideosReview(from environment: AppEnvironment) throws -> CategoryReviewData {
        let sized = try sizedAssets(from: environment)
        let thresholds = LargeOldThresholds(
            minBytes: CategoryDetectionDefaults.largeVideoMinBytes,
            olderThanOrEqualTo: Date(timeIntervalSinceNow: -CategoryDetectionDefaults.largeVideoMaxAgeDays * 24 * 3600)
        )
        let selected = LargeOldVideoSelection.select(sized, thresholds: thresholds)
        let assets = selected.map(\.asset)
        let proposal = BulkDeletionProposalComposer.compose(from: assets)
        return CategoryReviewData(review: CategoryReview.from(bulk: proposal), assets: indexed(assets))
    }

    // MARK: - Helper condivisi

    /// Byte reali per ogni asset dell'indice, dietro il port (exact se disponibile,
    /// altrimenti stima esplicita marcata). Stesso cablaggio di `LibraryFiguresReader`.
    private static func sizedAssets(from environment: AppEnvironment) throws -> [SizedAsset] {
        try environment.indexReader.assets(matching: .all).map { asset in
            SizedAsset(
                asset: asset,
                size: environment.byteResolver.byteSize(
                    forLocalIdentifier: asset.id,
                    fallbackEstimate: LibraryFiguresReader.fallbackEstimate(for: asset)
                )
            )
        }
    }

    /// Estrae il risultato di un'analisi cancellabile o **lancia** un errore esplicito:
    /// un'interruzione o un fallimento non diventano mai una lista vuota spacciata per
    /// «pulito» (L-COL-006). L'esito porta con sé il progresso raggiunto.
    private static func completed<Result: Equatable>(_ outcome: AnalysisOutcome<Result>) throws -> Result {
        switch outcome {
        case .completed(let value):
            return value
        case .cancelled(let at):
            throw AnalysisFailure("Analisi interrotta a \(at.processed)/\(at.total)")
        case .failed(let reason, _):
            throw reason
        }
    }

    /// Mappa id→asset (primo vince a parità di id), per etichette umane e miniature (A-3).
    private static func indexed(_ assets: [LibraryAsset]) -> [String: LibraryAsset] {
        Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
