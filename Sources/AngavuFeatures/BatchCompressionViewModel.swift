import AngavuDomain
import AngavuData
import Foundation
import Observation

// B-2d — Driver del BATCH di compressione (guscio UI, async).
//
// Concatena i pezzi puri e già verdi in un flusso a coda:
//   • CompressionCandidateSource / VideoSpecProviding → BatchCompressionEstimator
//     (B-2a) per la stima aggregata sui top-N video più grandi;
//   • BatchCompressionSelection (B-2b) come stato di selezione opt-in;
//   • BatchCompressionRun (B-2c) come riduttore del progresso e degli esiti;
//   • VideoExportCoordinator (T-081) per la ricodifica cancellabile e
//     CompressedReplacementPlanner (T-082) per instradare OGNI originale al
//     DeletionFlow (rete di sicurezza) — mai un delete diretto, mai perdita di dati.
//
// La logica pura vive nel Domain (testata come oracolo); qui c'è solo
// l'orchestrazione async, che gira off-main (l'export reale AVFoundation è
// device-only, compilato in CI, runtime dichiarato non coperto — L-COL-006).
// Altitudine: Features → Data/Domain (nessuna dipendenza vietata).

@Observable
public final class BatchCompressionViewModel {

    /// Fase del flusso batch dal punto di vista della schermata.
    public enum Phase: Equatable, Sendable {
        /// Si scelgono i video (stima visibile), nulla in esecuzione.
        case selecting
        /// La coda è in esecuzione: progresso determinato + annulla.
        case running
        /// La coda è conclusa (esiti aggregati) o cancellata.
        case done
    }

    public private(set) var phase: Phase = .selecting
    public private(set) var candidates: [CompressionCandidate] = []
    public private(set) var estimate = BatchCompressionEstimate(
        perItem: [], unestimableIds: [], total: .estimated(bytes: 0)
    )
    public private(set) var selection = BatchCompressionSelection(available: [])
    public private(set) var run: BatchCompressionRun?
    /// Preset di ricodifica, comune al batch.
    public var preset: HEVCPreset = .balanced
    /// Quanti candidati la stima ha coperto (per l'avviso onesto del cap).
    public private(set) var estimatedCount = 0

    private let coordinator: VideoExportCoordinator
    /// FSE-J3: installer della sostituzione reale (salva il compresso + elimina
    /// l'originale, solo dopo un salvataggio verificato). Iniettato dalla radice di
    /// composizione; i test iniettano una spia.
    private let installer: any CompressedAssetInstalling
    private var optIn = CompressionOptIn()
    private var cancellation = CancellationToken()
    /// Spec risolte off-device dell'ultimo `computeEstimate`, per ricalcolare la
    /// stima al cambio di preset SENZA rileggere il dispositivo (le spec non
    /// dipendono dal preset; solo il fattore di bitrate cambia).
    private var resolvedItems: [BatchCompressionItem] = []

    public init(exporter: any VideoExporting, installer: any CompressedAssetInstalling) {
        self.coordinator = VideoExportCoordinator(exporter: exporter)
        self.installer = installer
    }

    // MARK: - Candidati e selezione

    /// Imposta i candidati e ricostruisce una selezione fresca (nulla preselezionato).
    public func setCandidates(_ candidates: [CompressionCandidate]) {
        self.candidates = candidates
        self.selection = BatchCompressionSelection(available: candidates.map(\.id))
    }

    public func toggle(_ id: String) { selection.toggle(id) }
    public func selectAll() { selection.selectAll() }
    public func selectNone() { selection.selectNone() }

    /// Riepilogo della selezione rispetto alla stima (puro, testato).
    public var summary: BatchCompressionSummary {
        BatchCompressionSummary(estimate: estimate, selection: selection)
    }

    /// Numero totale di candidati (per l'avviso del cap della stima).
    public var totalCandidateCount: Int { candidates.count }

    // MARK: - Stima (off-main)

    /// Legge la `VideoSpec` on-device per i primi `cap` candidati (i più grandi,
    /// già ordinati dalla sorgente) e calcola la stima di batch. Il cap evita di
    /// ricalcolare su migliaia di video (perf); la copertura ridotta è dichiarata a
    /// schermo (`BatchCompressionCopy.estimateCapNotice`). Una spec assente resta
    /// dichiarata non stimabile, mai inventata.
    @MainActor
    public func computeEstimate(cap: Int, using specProvider: any VideoSpecProviding) async {
        let top = Array(candidates.prefix(cap))
        var items: [BatchCompressionItem] = []
        items.reserveCapacity(top.count)
        for candidate in top {
            let spec = await specProvider.videoSpec(
                forLocalIdentifier: candidate.id,
                originalBytes: candidate.originalBytes
            )
            items.append(BatchCompressionItem(id: candidate.id, spec: spec))
        }
        self.resolvedItems = items
        self.estimate = BatchCompressionEstimator.estimate(items: items, preset: preset)
        self.estimatedCount = top.count
    }

    /// Ricalcola la stima dalle spec già risolte col preset corrente (nessuna
    /// rilettura del dispositivo). Da chiamare al cambio di preset.
    public func reestimate() {
        estimate = BatchCompressionEstimator.estimate(items: resolvedItems, preset: preset)
    }

    // MARK: - Esecuzione della coda

    // @MainActor: stessa ragione del fix crash di `confirmAndDelete` — `publish()` muta
    // `run`/`phase` (stato @Observable). Senza, questo metodo async di una classe non
    // isolata girerebbe off-main e le mutazioni osservabili avverrebbero fuori dal main
    // thread (crash SwiftUI durante il ridisegno). Gli `await` interni (export, install)
    // saltano comunque fuori per il lavoro pesante e rientrano sul main per il `publish`.
    /// Avvia la compressione dei video selezionati, in ordine.
    ///
    /// GATE (opt-in + rete di sicurezza): senza `previewConfirmed` (la conferma
    /// dell'anteprima batch) l'exporter NON è invocato — ogni item è `failed`
    /// dichiarato e nessun sorgente è toccato. Con conferma: per ciascun video
    /// export → (su success) sostituzione via `DeletionFlow` (originale a «Eliminati
    /// di recente»). Un FALLIMENTO per-item non aborta il batch; la CANCELLAZIONE
    /// lascia i residui non processati. Il progresso è pubblicato dopo ogni item.
    @MainActor
    @discardableResult
    public func start(previewConfirmed: Bool) async -> BatchCompressionRun {
        let queue = selection.selectedInOrder
        var current = BatchCompressionRun(queue: queue)

        optIn.grantConsent(for: queue)
        guard previewConfirmed, optIn.canStart(queue) else {
            for index in current.queue.indices {
                current.record(
                    .failed(reason: "Consenso/anteprima mancante: la compressione non parte."),
                    at: index
                )
            }
            publish(current, phase: .done)
            return current
        }

        cancellation = CancellationToken()
        publish(current, phase: .running)

        while let index = current.nextPendingIndex {
            if cancellation.isCancelled {
                current.cancel()
                break
            }
            let id = current.queue[index]
            let outcome = await coordinator.run(
                sourceLocalIdentifier: id,
                preset: preset,
                cancellation: cancellation
            )
            await apply(outcome, at: index, id: id, to: &current)
            publish(current, phase: .running)
        }

        publish(current, phase: .done)
        return current
    }

    /// Richiede l'annullamento cooperativo della coda in corso.
    public func requestCancel() {
        cancellation.cancel()
    }

    /// Torna alla selezione (nuova coda). Il consenso è revocato.
    public func reset() {
        run = nil
        phase = .selecting
        optIn.revoke()
        selection.selectNone()
        cancellation = CancellationToken()
    }

    // MARK: - Passi privati

    /// Traduce l'esito dell'export nell'esito di coda. Su export riuscito il piano puro
    /// (`CompressedReplacementPlanner`) fa da gate e, se approva, la sostituzione è
    /// ESEGUITA DAVVERO (FSE-J3): l'installer salva il compresso in libreria e, solo dopo
    /// un salvataggio verificato, elimina l'originale (→ «Eliminati di recente»). Se il
    /// salvataggio fallisce, l'originale resta intatto (mai perdita di dati).
    private func apply(
        _ outcome: VideoExportOutcome,
        at index: Int,
        id: String,
        to run: inout BatchCompressionRun
    ) async {
        switch outcome {
        case .cancelled:
            run.cancel()
        case .failed(let reason):
            run.record(.failed(reason: reason), at: index)
        case .success:
            await applySuccess(outcome, at: index, id: id, to: &run)
        }
    }

    /// Passo di sostituzione reale su export riuscito. Estratto per tenere corto il corpo
    /// del loop (function_body_length) senza cambiare il comportamento.
    private func applySuccess(
        _ outcome: VideoExportOutcome,
        at index: Int,
        id: String,
        to run: inout BatchCompressionRun
    ) async {
        guard case .success(let outputBytes, let outputURL, let metadata) = outcome else { return }
        let planned = CompressedReplacementPlanner.plan(
            outcome: outcome,
            exportVerifiedIntegral: true,
            previewConfirmed: true,
            originalId: id
        )
        guard case .success = planned else {
            if case .failure(let error) = planned {
                run.record(.failed(reason: String(describing: error)), at: index)
            }
            return
        }
        // Piano approvato → ESEGUI la sostituzione reale (salva compresso + elimina originale).
        let installed = await installer.install(
            compressedAt: outputURL, originalId: id, metadata: metadata
        )
        switch installed {
        case .installed:
            run.record(.succeeded(outputBytes: outputBytes), at: index)
        case .saveFailed(let reason), .deleteFailed(let reason):
            // Salvataggio/eliminazione non completati → non è un successo onesto.
            // Su `saveFailed` l'originale è intatto; su `deleteFailed` entrambi restano.
            run.record(.failed(reason: reason), at: index)
        }
    }

    private func publish(_ run: BatchCompressionRun, phase: Phase) {
        self.run = run
        self.phase = phase
    }
}
