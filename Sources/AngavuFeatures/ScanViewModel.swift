import AngavuDomain
import AngavuData
import Observation

// T-111 (wiring) — Flusso di scansione come view-model osservabile.
//
// Orchestra: permessi PhotoKit → enumerazione → mapping/indicizzazione, con stato
// esplicito e stop cooperativo (motore T-004). Nessun accesso limited spacciato
// per totale: lo stato `completed` porta il flag `partialCount`. La logica sta
// dietro i port dell'AppEnvironment, quindi è testabile con fake, senza device.

/// Stato esplicito della scansione. Mai un blocco muto: ogni esito è uno di questi.
public enum ScanState: Equatable, Sendable {
    case idle
    case requestingPermission
    /// In corso: il progresso è UNIFICATO su tutte le fasi del lavoro vero
    /// (indice → byte per-asset → residenza device), così la barra del tasto copre
    /// l'intera scansione, non solo l'indicizzazione.
    case scanning(ScanPipelineProgress)
    /// Indicizzati `indexed` asset; `partialCount` vero se l'accesso era limited.
    case completed(indexed: Int, partialCount: Bool)
    case cancelled(AnalysisProgress)
    case failed(String)
}

@Observable
public final class ScanViewModel {
    /// Messaggio di fallimento quando l'accesso alla libreria non è concesso.
    /// Esposto come costante così che la presentazione possa distinguere questo
    /// fallimento (per offrire "Apri Impostazioni") senza string-matching fragile.
    public static let accessDeniedMessage = "Accesso alla libreria non concesso."

    public private(set) var state: ScanState = .idle

    /// Numeri veri della dashboard calcolati DENTRO la scansione unificata (fasi 2-3),
    /// pronti da cachare sopra le view: così, aprendo «Numeri veri», la dashboard è
    /// istantanea — nessuna seconda attesa «Calcolo dei numeri veri…», nessun
    /// ricalcolo. `nil` finché una scansione non è arrivata a `completed`, o se le fasi
    /// dei numeri sono state saltate (cancellazione/errore: la dashboard ricalcolerà).
    public private(set) var figures: DashboardScreen?

    /// FSE-F1 — «un'unica scansione fa tutto»: le review di categoria calcolate DENTRO
    /// la scansione unificata (fasi dei rilevatori), pronte da cachare sopra le view
    /// (chiavi `.category(...)`) → aprire una categoria è istantaneo, mai una nuova
    /// scansione al tap. Contiene SOLO le categorie effettivamente raggiunte e
    /// completate: una scansione cancellata a metà lascia le categorie non raggiunte
    /// FUORI dalla mappa (verranno calcolate al tap), mai un risultato parziale
    /// spacciato per completo. `CategoryReviewData` è un tipo interno al modulo, quindi
    /// la proprietà è interna (letta dalla Home, che popola la cache). Vuota finché una
    /// scansione non raggiunge le fasi dei rilevatori.
    private(set) var categoryResults: [CleanupCategory: CategoryReviewData] = [:]

    private let environment: AppEnvironment
    private let authorizer: any PhotoLibraryAuthorizing
    private let enumerator: any PhotoAssetEnumerating
    private let indexWriter: any AssetIndexWriting
    /// FSE-A1: strumentazione di misura. Ogni fase è racchiusa in un intervallo
    /// signpost (attribuzione dei tempi in Instruments, §7). Default reale su Apple,
    /// no-op altrove; i test iniettano un fake che conta begin/end.
    private let signpost: any ScanSignposting

    public init(
        environment: AppEnvironment,
        signpost: any ScanSignposting = liveScanSignpost()
    ) {
        self.environment = environment
        self.authorizer = environment.authorizer
        self.enumerator = environment.enumerator
        self.indexWriter = environment.indexWriter
        self.signpost = signpost
    }

    /// Esegue la scansione completa e restituisce lo stato finale. Idempotente
    /// rispetto allo stato: lo aggiorna passo per passo.
    @discardableResult
    public func run(cancellation: CancellationToken = CancellationToken()) async -> ScanState {
        // Nuova scansione: i numeri veri e le review di categoria della precedente non
        // valgono più (l'indice viene ricostruito).
        figures = nil
        categoryResults = [:]
        state = .requestingPermission
        let access = await authorizer.requestAccess()
        let decision = PhotoAccessPolicy.decide(for: access)

        // Accesso negato / non determinato: nessuna enumerazione tentata.
        guard decision.shouldEnumerate else {
            state = .failed(Self.accessDeniedMessage)
            return state
        }

        // FASE 1 — indice (enumerazione + mapping + upsert). Un solo intervallo di
        // misura racchiude l'intera fase (FSE-A1): apre alla prima riga, chiude a
        // qualunque via d'uscita (completato/cancellato/errore) via `measure`.
        let indexResult: IndexOutcome = signpost.measure(.indexing) {
            let raws = enumerator.enumerateRawAssets()
            report(.indexing, AnalysisProgress(processed: 0, total: raws.count))

            let outcome = LibraryAssetMapper.mapBatch(raws, cancellation: cancellation) { progress in
                self.report(.indexing, progress)
            }
            switch outcome {
            case .completed(let mapped):
                do {
                    try indexWriter.upsert(mapped)
                    return .completed(mapped)
                } catch {
                    return .failed(String(describing: error))
                }
            case .cancelled(let at):
                // Cancellata: nessuna indicizzazione dei blocchi non processati.
                return .cancelled(at)
            case .failed(let reason, _):
                return .failed(reason.message)
            }
        }

        let assets: [LibraryAsset]
        switch indexResult {
        case .completed(let mapped):
            assets = mapped
        case .cancelled(let at):
            state = .cancelled(at)
            return state
        case .failed(let message):
            state = .failed(message)
            return state
        }

        // FASI 2-3 — numeri veri (byte per-asset + residenza device), stessa barra.
        // Un fallimento QUI non annulla la scansione: l'indice è scritto (fatto reale),
        // i numeri restano non calcolati e la dashboard li ricalcolerà. Una
        // cancellazione, invece, è volontà dell'utente → esito `cancelled`.
        computeFigures(cancellation: cancellation) { cancelledAt in
            self.state = .cancelled(cancelledAt)
        }
        if case .cancelled = state { return state }

        // FASI 4-8 — rilevatori di categoria (FSE-F1): la STESSA passata calcola anche
        // duplicati/simili/sfocate/screenshot/grandi-vecchi e ne cacha i risultati, così
        // aprire una categoria è istantaneo. Un rilevatore che fallisce lascia la SUA
        // categoria non-cachata (verrà calcolata al tap) senza abortire la scansione;
        // una cancellazione, invece, è volontà dell'utente → esito `cancelled`.
        computeCategoryResults(cancellation: cancellation) { cancelledAt in
            self.state = .cancelled(cancelledAt)
        }
        if case .cancelled = state { return state }

        state = .completed(indexed: assets.count, partialCount: decision.isPartialCount)
        return state
    }

    /// Aggiorna lo stato con un progresso di fase, come parte dell'unica barra.
    private func report(_ stage: ScanPipelineProgress.Stage, _ progress: AnalysisProgress) {
        state = .scanning(ScanPipelineProgress(stage: stage, stageProgress: progress))
    }

    /// FASI 2-3: risolve i byte per-asset e misura la residenza device, riportando il
    /// progresso sull'unica barra, e compone i `DashboardScreen` in `figures`. Su
    /// cancellazione invoca `onCancelled` col progresso raggiunto (l'esito diventa
    /// `cancelled`); su errore lascia `figures == nil` senza abortire la scansione.
    private func computeFigures(
        cancellation: CancellationToken,
        onCancelled: (AnalysisProgress) -> Void
    ) {
        // FASE 2 — byte reali per-asset + aggregazione. Intervallo di misura FSE-A1.
        let resolveOutcome = signpost.measure(.resolvingSizes) {
            LibraryFiguresReader.resolve(from: environment, cancellation: cancellation) { progress in
                self.report(.resolvingSizes, progress)
            }
        }
        let resolved: ResolvedLibrary
        switch resolveOutcome {
        case .completed(let value): resolved = value
        case .cancelled(let at): onCancelled(at); return
        case .failed: figures = nil; return
        }

        // FASE 3 — residenza per-asset reale (numero device preciso, P0-2b).
        // Intervallo di misura FSE-A1 (candidato #1 a ottimizzazione, §1.7/FSE-G).
        report(.measuringDeviceSpace, AnalysisProgress(processed: 0, total: resolved.probeItems.count))
        let residencyOutcome = signpost.measure(.measuringDeviceSpace) {
            ResidencyAggregator.measure(
                items: resolved.probeItems,
                probe: environment.residencyProbe,
                cancellation: cancellation
            ) { progress in
                self.report(.measuringDeviceSpace, progress)
            }
        }
        if case .cancelled(let at) = residencyOutcome { onCancelled(at); return }

        // Misura reale e completa ⇒ numero device preciso; altrimenti caveat onesto.
        let measurement = ResidencyAggregator.measurement(from: residencyOutcome)
        let figuresValue = LibraryFiguresReader.figures(
            from: resolved,
            environment: environment,
            measuredResidency: measurement.isDeterminate ? measurement : nil
        )
        figures = DashboardScreen(figures: figuresValue)
    }

    /// FASI 4-8 (FSE-F1): calcola le review di categoria nella stessa passata e le
    /// raccoglie in `categoryResults` (pronte per la cache sopra le view). Ogni
    /// categoria è una fase della barra unificata (`scanStage`), misurata da un
    /// intervallo signpost dedicato (FSE-A1, 1:1). Invarianti di onestà:
    ///  • una categoria COMPLETATA finisce in `categoryResults` (cache hit al tap);
    ///  • una categoria non ancora RAGGIUNTA (cancellazione a metà) resta FUORI dalla
    ///    mappa → verrà calcolata al tap, mai un parziale spacciato per completo;
    ///  • un ERRORE del rilevatore (non una cancellazione) lascia la sola categoria
    ///    non-cachata e prosegue con le altre (la scansione non aborta);
    ///  • la barra non arretra: ogni fase parte dalla fine della precedente e viene
    ///    chiusa a fase completa prima di passare alla successiva.
    private func computeCategoryResults(
        cancellation: CancellationToken,
        onCancelled: (AnalysisProgress) -> Void
    ) {
        let categories = CleanupCategory.allCases
        let total = categories.count
        var done = 0
        for category in categories {
            // Cancellazione RILEVATA al confine di categoria: le raggiunte sono cachate,
            // questa e le successive no.
            if cancellation.isCancelled {
                onCancelled(AnalysisProgress(processed: done, total: total))
                return
            }
            let stage = category.scanStage
            let outcome: CategoryOutcome = signpost.measure(ScanSignpostPhase(stage)) {
                do {
                    let data = try CategoryReviewSource.reviewData(
                        for: category,
                        from: environment,
                        cancellation: cancellation
                    ) { progress in
                        self.report(stage, progress)
                    }
                    return .completed(data)
                } catch {
                    return .failed
                }
            }
            switch outcome {
            case .completed(let data):
                categoryResults[category] = data
                done += 1
            case .failed:
                // Un rilevatore che lancia PERCHÉ cancellato (via `completed(_:)`) è
                // volontà dell'utente: esito `cancelled`, categoria non-cachata. Un
                // errore genuino (token non cancellato) lascia solo questa categoria
                // fuori e prosegue.
                if cancellation.isCancelled {
                    onCancelled(AnalysisProgress(processed: done, total: total))
                    return
                }
            }
            // Chiude la fase corrente a «completa» prima della prossima: le categorie a
            // filtro puro (screenshot, grandi/vecchi) non riportano X/N, e questo snap
            // porta la barra alla fine della loro quota senza mai farla arretrare.
            report(stage, AnalysisProgress(processed: 1, total: 1))
        }
    }

    /// Esito d'una singola fase-categoria, catturato DENTRO l'intervallo di misura così
    /// che l'intervallo si chiuda prima di aggiornare `categoryResults`/lo stato.
    private enum CategoryOutcome {
        case completed(CategoryReviewData)
        case failed
    }

    /// Esito della FASE 1 (indice), catturato DENTRO l'intervallo di misura così che
    /// ogni via d'uscita chiuda l'intervallo prima che lo stato venga aggiornato.
    private enum IndexOutcome {
        case completed([LibraryAsset])
        case cancelled(AnalysisProgress)
        case failed(String)
    }
}
