import AngavuDomain
import AngavuData

// Test-double condivisi per i port di compressione video aggiunti all'AppEnvironment
// (guscio UI — schermata «Comprimi video»). I test che non esercitano la
// compressione iniettano questi no-op: non fabbricano numeri e non avviano nulla.
// Definiti una volta (internal, non `private`) e riusati da tutti i makeEnvironment
// del target, per non duplicare la stessa struct in ogni file.

struct NoopVideoExporter: VideoExporting {
    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        .cancelled
    }
}

struct NoopVideoSpecProvider: VideoSpecProviding {
    func videoSpec(forLocalIdentifier id: String, originalBytes: Int64) async -> VideoSpec? {
        nil
    }
}
