import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// B-2d — Driver del batch di compressione. Verifica l'orchestrazione async col
// riduttore puro: consenso/anteprima come gate, esiti per-item aggregati, un
// fallimento non aborta il batch, ogni successo instrada l'originale al DeletionFlow.
// L'export reale è device-only: qui si usa un fake (compilato+eseguito ovunque).

private final class FakeExporter: VideoExporting {
    /// Esito per id; default success se non specificato.
    let outcomes: [String: VideoExportOutcome]
    private(set) var exportCalls: [String] = []

    init(outcomes: [String: VideoExportOutcome] = [:]) { self.outcomes = outcomes }

    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        exportCalls.append(sourceLocalIdentifier)
        return outcomes[sourceLocalIdentifier]
            ?? .success(outputBytes: 100, metadata: VideoMetadata(creationDate: nil, latitude: nil, longitude: nil))
    }
}

private final class FakeSpecProvider: VideoSpecProviding {
    /// Restituisce `nil` per gli id in `missing`; altrimenti una spec valida.
    let missing: Set<String>
    init(missing: Set<String> = []) { self.missing = missing }

    func videoSpec(forLocalIdentifier id: String, originalBytes: Int64) async -> VideoSpec? {
        if missing.contains(id) { return nil }
        return VideoSpec(originalBytes: originalBytes, durationSeconds: 60, sourceBitrateBitsPerSec: 12_000_000)
    }
}

private func candidate(_ id: String, bytes: Int64) -> CompressionCandidate {
    CompressionCandidate(id: id, originalBytes: bytes, isSizeEstimated: false)
}

final class BatchCompressionFlowTests: XCTestCase {

    // Senza conferma dell'anteprima: l'exporter NON è invocato; ogni item è failed.
    func test_start_withoutPreviewConfirmed_neverExports() async {
        let exporter = FakeExporter()
        let vm = BatchCompressionViewModel(exporter: exporter)
        vm.setCandidates([candidate("a", bytes: 300), candidate("b", bytes: 200)])
        vm.selectAll()

        let run = await vm.start(previewConfirmed: false)

        XCTAssertTrue(exporter.exportCalls.isEmpty, "nessun avvio silenzioso senza conferma")
        XCTAssertEqual(run.failedCount, 2)
        XCTAssertEqual(vm.phase, .done)
    }

    // Selezione vuota (opt-in): niente coda, niente export.
    func test_start_emptySelection_isNoop() async {
        let exporter = FakeExporter()
        let vm = BatchCompressionViewModel(exporter: exporter)
        vm.setCandidates([candidate("a", bytes: 300)])

        let run = await vm.start(previewConfirmed: true)

        XCTAssertTrue(exporter.exportCalls.isEmpty)
        XCTAssertEqual(run.total, 0)
        XCTAssertTrue(run.isFinished)
    }

    // Batch 3 con 1 fallimento al 2°: la coda prosegue → {ok, failed, ok}.
    func test_start_perItemFailure_doesNotAbort() async {
        let exporter = FakeExporter(outcomes: ["b": .failed(reason: "export non riuscito")])
        let vm = BatchCompressionViewModel(exporter: exporter)
        // Ordine per dimensione desc: a(300) > b(200) > c(100).
        vm.setCandidates([candidate("a", bytes: 300), candidate("b", bytes: 200), candidate("c", bytes: 100)])
        vm.selectAll()

        let run = await vm.start(previewConfirmed: true)

        XCTAssertEqual(exporter.exportCalls, ["a", "b", "c"], "tutti processati, in ordine")
        XCTAssertEqual(run.succeededCount, 2)
        XCTAssertEqual(run.failedCount, 1)
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(vm.phase, .done)
    }

    // Solo i selezionati sono compressi (subset).
    func test_start_compressesOnlySelectedSubset() async {
        let exporter = FakeExporter()
        let vm = BatchCompressionViewModel(exporter: exporter)
        vm.setCandidates([candidate("a", bytes: 300), candidate("b", bytes: 200), candidate("c", bytes: 100)])
        vm.toggle("a")
        vm.toggle("c")

        let run = await vm.start(previewConfirmed: true)

        XCTAssertEqual(Set(exporter.exportCalls), ["a", "c"], "solo il sottoinsieme selezionato")
        XCTAssertFalse(exporter.exportCalls.contains("b"))
        XCTAssertEqual(run.total, 2)
        XCTAssertEqual(run.succeededCount, 2)
    }

    // La stima copre i top-N; una spec assente resta dichiarata non stimabile.
    func test_computeEstimate_capAndUnestimable() async {
        let vm = BatchCompressionViewModel(exporter: FakeExporter())
        vm.setCandidates([
            candidate("a", bytes: 300), candidate("b", bytes: 200), candidate("c", bytes: 100)
        ])
        let specs = FakeSpecProvider(missing: ["b"])

        await vm.computeEstimate(cap: 2, using: specs)

        XCTAssertEqual(vm.estimatedCount, 2, "cap=2 copre solo i primi 2 candidati")
        // 'a' stimabile, 'b' senza spec → dichiarato; 'c' fuori dal cap.
        XCTAssertEqual(vm.estimate.perItem.map(\.id), ["a"])
        XCTAssertEqual(vm.estimate.unestimableIds, ["b"])
    }
}
