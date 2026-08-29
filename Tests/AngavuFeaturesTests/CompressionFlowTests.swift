import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-116 — AC-116-1 / AC-116-2. Flusso di compressione: opt-in → export →
// sostituzione via DeletionFlow. Nessuna perdita di dati; nessun avvio senza consenso.

private final class FakeExporter: VideoExporting {
    let outcome: VideoExportOutcome
    private(set) var exportCalls: [String] = []
    init(outcome: VideoExportOutcome) { self.outcome = outcome }
    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        exportCalls.append(sourceLocalIdentifier)
        return outcome
    }
}

private func successOutcome(_ bytes: Int64) -> VideoExportOutcome {
    .success(
        outputBytes: bytes,
        outputURL: URL(fileURLWithPath: "/tmp/out.mov"),
        metadata: VideoMetadata(creationDate: nil, latitude: nil, longitude: nil)
    )
}

final class CompressionFlowTests: XCTestCase {

    // AC-116-1: consenso + export success verificato + anteprima confermata →
    // sostituzione: originale instradato al DeletionFlow (confirmed), compresso
    // pronto all'indice.
    func test_consentedVerifiedConfirmedProducesReplacementViaDeletionFlow() async {
        let exporter = FakeExporter(outcome: successOutcome(500))
        let vm = CompressionViewModel(exporter: exporter)

        XCTAssertTrue(vm.grantConsent(for: ["V1"]))
        let final = await vm.compress(
            originalId: "V1",
            preset: .balanced,
            exportVerifiedIntegral: true,
            previewConfirmed: true
        )

        guard case .done(let replacement) = final else { return XCTFail("atteso done, ottenuto \(final)") }
        XCTAssertEqual(replacement.originalId, "V1")
        XCTAssertEqual(replacement.compressed.outputBytes, 500, "il compresso è pronto all'indice")
        XCTAssertEqual(replacement.deletion.state, .confirmed(assets: ["V1"]),
                       "l'originale passa dal DeletionFlow, mai un delete diretto")
        XCTAssertEqual(exporter.exportCalls, ["V1"])
    }

    // AC-116-2: senza consenso opt-in l'avvio è rifiutato — l'exporter non è mai
    // invocato — finché il consenso non è dato.
    func test_withoutConsentStartIsRefusedUntilGranted() async {
        let exporter = FakeExporter(outcome: successOutcome(500))
        let vm = CompressionViewModel(exporter: exporter)

        let refused = await vm.compress(
            originalId: "V1",
            preset: .balanced,
            exportVerifiedIntegral: true,
            previewConfirmed: true
        )
        if case .failed = refused {} else { XCTFail("atteso failed senza consenso, ottenuto \(refused)") }
        XCTAssertTrue(exporter.exportCalls.isEmpty, "senza consenso l'export non parte")

        // Dato il consenso, ora parte e completa.
        XCTAssertTrue(vm.grantConsent(for: ["V1"]))
        let final = await vm.compress(
            originalId: "V1",
            preset: .balanced,
            exportVerifiedIntegral: true,
            previewConfirmed: true
        )
        guard case .done = final else { return XCTFail("atteso done dopo il consenso") }
        XCTAssertEqual(exporter.exportCalls, ["V1"])
    }

    // Nessuna perdita di dati: export success ma anteprima NON confermata → nessuna
    // sostituzione (failed), l'originale non è instradato all'eliminazione.
    func test_exportSuccessButPreviewNotConfirmedDoesNotReplace() async {
        let exporter = FakeExporter(outcome: successOutcome(500))
        let vm = CompressionViewModel(exporter: exporter)
        XCTAssertTrue(vm.grantConsent(for: ["V1"]))

        let final = await vm.compress(
            originalId: "V1",
            preset: .balanced,
            exportVerifiedIntegral: true,
            previewConfirmed: false
        )
        if case .failed = final {} else { XCTFail("atteso failed senza conferma anteprima") }
    }

    // Export fallito → stato failed, nessuna sostituzione.
    func test_exportFailurePropagates() async {
        let exporter = FakeExporter(outcome: .failed(reason: "codec"))
        let vm = CompressionViewModel(exporter: exporter)
        XCTAssertTrue(vm.grantConsent(for: ["V1"]))

        let final = await vm.compress(
            originalId: "V1",
            preset: .balanced,
            exportVerifiedIntegral: true,
            previewConfirmed: true
        )
        if case .failed = final {} else { XCTFail("atteso failed su export fallito") }
    }

    // La stima è sempre marcata come stima (mai un numero garantito).
    func test_estimateIsMarkedEstimated() {
        let vm = CompressionViewModel(exporter: FakeExporter(outcome: .cancelled))
        let spec = VideoSpec(originalBytes: 1_000_000, durationSeconds: 10, sourceBitrateBitsPerSec: 8_000_000)
        let saving = vm.estimate(spec: spec, preset: .balanced)
        XCTAssertFalse(saving.isExact, "il risparmio della compressione è sempre una stima")
    }
}
