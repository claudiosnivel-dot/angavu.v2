import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-J3 — Sostituzione compressa REALE cablata (censimento C2), Livello A (CI, no device).
//
// Prima: l'export girava ma `apply()` calcolava solo il piano puro → nessun
// `PHAssetCreationRequest`, nessuna eliminazione → niente spazio liberato (no-op).
// Qui due seam chiudono il buco in CI:
//   (1) ViewModel → installer: su export riuscito il batch INVOCA DAVVERO l'installer
//       (salva+elimina) una volta con l'id giusto; su export fallito non installa; su
//       salvataggio fallito l'item è failed (mai un falso successo).
//   (2) Installer (orchestrazione pura): salva PRIMA di eliminare — se il salvataggio
//       fallisce, il deleter dell'originale NON è mai chiamato (mai perdita di dati).

private final class StubExporter: VideoExporting {
    let outcome: VideoExportOutcome
    init(_ outcome: VideoExportOutcome) { self.outcome = outcome }
    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        outcome
    }
}

private func successOutcome(bytes: Int64 = 100) -> VideoExportOutcome {
    .success(
        outputBytes: bytes,
        outputURL: URL(fileURLWithPath: "/tmp/compressed.mov"),
        metadata: VideoMetadata(creationDate: nil, latitude: nil, longitude: nil)
    )
}

private func candidate(_ id: String) -> CompressionCandidate {
    CompressionCandidate(id: id, originalBytes: 1_000, isSizeEstimated: false)
}

// MARK: - Seam 1 — il ViewModel invoca DAVVERO l'installer

final class CompressionReplacementWiringTests: XCTestCase {

    // AC-FSE-J3-1 (invocato una volta): export riuscito + piano approvato → l'installer è
    // invocato UNA volta con ESATTAMENTE l'id sorgente, e l'item risulta succeeded.
    func test_batchStart_invokesInstallerOnce_onExportSuccess() async {
        let installer = SpyCompressedInstaller(result: .installed)
        let vm = BatchCompressionViewModel(exporter: StubExporter(successOutcome()), installer: installer)
        vm.setCandidates([candidate("V1")])
        vm.selectAll()

        let run = await vm.start(previewConfirmed: true)

        XCTAssertEqual(installer.installedIds, ["V1"], "l'installer è invocato una volta con l'id sorgente")
        XCTAssertEqual(run.succeededCount, 1)
        XCTAssertEqual(run.failedCount, 0)
    }

    // AC-FSE-J3-1 (non installa se l'export non riesce): export fallito → l'installer NON è
    // mai invocato (nessun salvataggio/eliminazione su un export non riuscito).
    func test_batchStart_doesNotInstall_onExportFailure() async {
        let installer = SpyCompressedInstaller(result: .installed)
        let vm = BatchCompressionViewModel(
            exporter: StubExporter(.failed(reason: "export non riuscito")), installer: installer
        )
        vm.setCandidates([candidate("V1")])
        vm.selectAll()

        let run = await vm.start(previewConfirmed: true)

        XCTAssertTrue(installer.installedIds.isEmpty, "nessuna installazione su export fallito")
        XCTAssertEqual(run.failedCount, 1)
    }

    // AC-FSE-J3-1 (installer fallisce → item failed): se il salvataggio fallisce, l'item è
    // failed (mai un falso successo) — il VM riporta l'esito onesto dell'installer.
    func test_batchStart_recordsFailure_whenInstallerSaveFails() async {
        let installer = SpyCompressedInstaller(result: .saveFailed(reason: "disco pieno"))
        let vm = BatchCompressionViewModel(exporter: StubExporter(successOutcome()), installer: installer)
        vm.setCandidates([candidate("V1")])
        vm.selectAll()

        let run = await vm.start(previewConfirmed: true)

        XCTAssertEqual(
            installer.installedIds, ["V1"],
            "l'installer è comunque invocato (è lui il gate del salvataggio)"
        )
        XCTAssertEqual(run.succeededCount, 0)
        XCTAssertEqual(run.failedCount, 1, "salvataggio fallito → item failed, mai un falso successo")
    }
}

// MARK: - Seam 2 — l'installer salva PRIMA di eliminare (mai perdita di dati)

private final class StubSaver: CompressedVideoSaving {
    let result: CompressedSaveResult
    private(set) var saveCount = 0
    init(_ result: CompressedSaveResult) { self.result = result }
    func save(compressedAt url: URL, metadata: VideoMetadata) async -> CompressedSaveResult {
        saveCount += 1
        return result
    }
}

private final class SpyDeleter: AssetDeleting {
    private(set) var deletedBatches: [[String]] = []
    var result: BatchDeletionResult = .success
    func delete(ids: [String]) async -> BatchDeletionResult {
        deletedBatches.append(ids)
        return result
    }
}

final class SafeCompressedInstallerTests: XCTestCase {

    private let metadata = VideoMetadata(creationDate: nil, latitude: nil, longitude: nil)
    private let url = URL(fileURLWithPath: "/tmp/compressed.mov")

    // AC-FSE-J3-1 (salva → elimina): salvataggio riuscito → l'originale è eliminato UNA volta
    // con l'id giusto, esito `.installed`.
    func test_install_savesThenDeletesOriginal_onSaveSuccess() async {
        let saver = StubSaver(.saved)
        let deleter = SpyDeleter()
        let installer = SafeCompressedAssetInstaller(saver: saver, deleter: deleter)

        let result = await installer.install(compressedAt: url, originalId: "V1", metadata: metadata)

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(saver.saveCount, 1)
        XCTAssertEqual(deleter.deletedBatches, [["V1"]],
                       "l'originale è eliminato una volta, solo DOPO il salvataggio")
    }

    // AC-FSE-J3-1 (salvataggio fallito → NESSUNA delete): l'originale NON è mai toccato →
    // nessuna perdita di dati. È l'invariante anti-perdita, ora ORACOLO in CI (non device-only).
    func test_install_neverDeletesOriginal_onSaveFailure() async {
        let saver = StubSaver(.failed(reason: "disco pieno"))
        let deleter = SpyDeleter()
        let installer = SafeCompressedAssetInstaller(saver: saver, deleter: deleter)

        let result = await installer.install(compressedAt: url, originalId: "V1", metadata: metadata)

        XCTAssertEqual(result, .saveFailed(reason: "disco pieno"))
        XCTAssertTrue(deleter.deletedBatches.isEmpty,
                      "salvataggio fallito → l'originale NON è eliminato (mai perdita di dati)")
    }

    // Salvato ma delete fallita → `deleteFailed` (compresso e originale restano entrambi:
    // nessuna perdita, l'esito è onesto).
    func test_install_reportsDeleteFailed_whenDeletionFails() async {
        let saver = StubSaver(.saved)
        let deleter = SpyDeleter()
        deleter.result = .failed(reason: "errore di sistema")
        let installer = SafeCompressedAssetInstaller(saver: saver, deleter: deleter)

        let result = await installer.install(compressedAt: url, originalId: "V1", metadata: metadata)

        XCTAssertEqual(result, .deleteFailed(reason: "errore di sistema"))
        XCTAssertEqual(deleter.deletedBatches, [["V1"]])
    }
}
