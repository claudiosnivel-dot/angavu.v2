import AngavuDomain
import AngavuData
import Observation

// T-116 (wiring) — Compressione video: stima → gate opt-in → export → sostituzione.
//
// Concatena i pezzi già verdi del macrotask video_compression con stato esplicito:
//   • CompressionEstimator (T-080) per la stima marcata;
//   • CompressionOptIn (T-080) come gate: nessun avvio senza consenso (AC-116-2);
//   • VideoExportCoordinator/VideoExporting (T-081) per la ricodifica cancellabile;
//   • CompressedReplacementPlanner (T-082) per la sostituzione SOLO dopo export
//     verificato + anteprima confermata; l'originale è instradato al DeletionFlow
//     (T-050), mai eliminato direttamente (AC-116-1).
// Nessuna logica di dominio nuova; l'export reale (AVFoundation) è dietro il port.

/// Stato esplicito del flusso di compressione. Ogni esito è uno di questi.
public enum CompressionState: Equatable, Sendable {
    case idle
    /// Stima del risparmio calcolata (sempre marcata come stima).
    case estimated(ByteSize)
    /// Consenso opt-in registrato per il batch dato.
    case consented(assets: [String])
    /// Export in corso per l'id dato.
    case exporting(String)
    /// Sostituzione in corso (export riuscito e verificato) per l'id dato.
    case replacing(String)
    /// Completato: piano di sostituzione pronto (originale verso Eliminati di recente).
    case done(CompressedReplacement)
    /// Cancellato (stop cooperativo): sorgente intatto.
    case cancelled
    case failed(String)
}

@Observable
public final class CompressionViewModel {
    public private(set) var state: CompressionState = .idle

    private var optIn = CompressionOptIn()
    private let coordinator: VideoExportCoordinator

    public init(exporter: any VideoExporting) {
        self.coordinator = VideoExportCoordinator(exporter: exporter)
    }

    /// Passo 1 — stima del risparmio (sempre `ByteSize.estimated`, mai garantita).
    @discardableResult
    public func estimate(spec: VideoSpec, preset: HEVCPreset) -> ByteSize {
        let saving = CompressionEstimator.estimatedSaving(for: spec, preset: preset)
        state = .estimated(saving)
        return saving
    }

    /// Passo 2 — consenso opt-in esplicito per un batch. Un batch vuoto è rifiutato.
    @discardableResult
    public func grantConsent(for ids: [String]) -> Bool {
        let granted = optIn.grantConsent(for: ids)
        if granted { state = .consented(assets: ids) }
        return granted
    }

    /// Passo 3 — comprime un video del batch consentito: export → (su success
    /// verificato + anteprima confermata) sostituzione via DeletionFlow.
    ///
    /// Gate opt-in (AC-116-2): senza consenso che copra l'id, l'avvio è RIFIUTATO —
    /// l'exporter non viene invocato e lo stato diventa `failed`, finché il consenso
    /// non è dato. Con consenso, export success + verifica + anteprima confermata →
    /// `done` con l'originale instradato all'eliminazione (AC-116-1).
    @discardableResult
    public func compress(
        originalId: String,
        preset: HEVCPreset,
        exportVerifiedIntegral: Bool,
        previewConfirmed: Bool,
        cancellation: CancellationToken = CancellationToken()
    ) async -> CompressionState {
        guard optIn.canStart([originalId]) else {
            state = .failed("Consenso opt-in mancante: la compressione non parte senza consenso.")
            return state
        }

        state = .exporting(originalId)
        let outcome = await coordinator.run(
            sourceLocalIdentifier: originalId,
            preset: preset,
            cancellation: cancellation
        )

        switch outcome {
        case .cancelled:
            state = .cancelled
        case .failed(let reason):
            state = .failed(reason)
        case .success:
            state = .replacing(originalId)
            let planned = CompressedReplacementPlanner.plan(
                outcome: outcome,
                exportVerifiedIntegral: exportVerifiedIntegral,
                previewConfirmed: previewConfirmed,
                originalId: originalId
            )
            switch planned {
            case .success(let replacement):
                state = .done(replacement)
            case .failure(let error):
                state = .failed(String(describing: error))
            }
        }
        return state
    }
}
