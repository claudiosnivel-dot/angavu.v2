import AngavuDomain
import AngavuData
import Foundation

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

/// FSE-J3 — Spia riusabile dell'installer: registra ogni invocazione (url, id) e
/// restituisce un esito configurabile. Sta al posto dell'adapter PhotoKit reale nei
/// test del *seam* della sostituzione (compilata+eseguita ovunque, nessun device).
final class SpyCompressedInstaller: CompressedAssetInstalling {
    private(set) var installedIds: [String] = []
    private(set) var installedURLs: [URL] = []
    var result: CompressedInstallResult

    init(result: CompressedInstallResult = .installed) { self.result = result }

    func install(
        compressedAt url: URL,
        originalId: String,
        metadata: VideoMetadata
    ) async -> CompressedInstallResult {
        installedURLs.append(url)
        installedIds.append(originalId)
        return result
    }
}
