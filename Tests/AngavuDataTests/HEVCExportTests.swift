import XCTest
import AngavuDomain
@testable import AngavuData

// T-081 — AC-081-1 / AC-081-2 / AC-081-3. Contratto dell'export via fake exporter
// (l'adapter reale AVFoundation gira su device; qui si verifica il contratto/coordinator).

private final class FakeExporter: VideoExporting {
    let outcome: VideoExportOutcome
    let respectCancellation: Bool
    private(set) var callCount = 0

    init(outcome: VideoExportOutcome, respectCancellation: Bool = false) {
        self.outcome = outcome
        self.respectCancellation = respectCancellation
    }

    func export(
        sourceLocalIdentifier: String,
        preset: HEVCPreset,
        cancellation: CancellationToken
    ) async -> VideoExportOutcome {
        callCount += 1
        if respectCancellation, cancellation.isCancelled { return .cancelled }
        return outcome
    }
}

final class HEVCExportTests: XCTestCase {

    private let meta = VideoMetadata(
        creationDate: Date(timeIntervalSince1970: 1_000),
        latitude: 45.07,
        longitude: 7.68
    )

    // AC-081-1: export success → l'output conserva i metadati (data/luogo) del sorgente.
    func test_success_preservesMetadata() async {
        let outputURL = URL(fileURLWithPath: "/tmp/out.mov")
        let fake = FakeExporter(outcome: .success(outputBytes: 50_000_000, outputURL: outputURL, metadata: meta))
        let coordinator = VideoExportCoordinator(exporter: fake)

        let outcome = await coordinator.run(
            sourceLocalIdentifier: "vid1",
            preset: .balanced,
            cancellation: CancellationToken()
        )

        guard case .success(let bytes, _, let metadata) = outcome else {
            return XCTFail("atteso success, ottenuto \(outcome)")
        }
        XCTAssertEqual(bytes, 50_000_000)
        XCTAssertEqual(metadata, meta)
        XCTAssertEqual(fake.callCount, 1)
    }

    // AC-081-2: cancellazione richiesta prima dell'avvio → esito cancelled, senza
    // nemmeno invocare l'exporter (nessun blocco a 0%).
    func test_cancellationBeforeStart_yieldsCancelledAndSkipsExport() async {
        let outputURL = URL(fileURLWithPath: "/tmp/out.mov")
        let fake = FakeExporter(outcome: .success(outputBytes: 1, outputURL: outputURL, metadata: meta))
        let coordinator = VideoExportCoordinator(exporter: fake)
        let token = CancellationToken()
        token.cancel()

        let outcome = await coordinator.run(
            sourceLocalIdentifier: "vid1",
            preset: .balanced,
            cancellation: token
        )

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(fake.callCount, 0, "con cancellazione pre-avvio l'export non parte")
    }

    // AC-081-3: export fallito → esito failed(reason) visibile; il coordinator non
    // ha alcun potere sul sorgente (la sostituzione è un passo separato, T-082).
    func test_failure_isVisibleAndSourceUntouched() async {
        let fake = FakeExporter(outcome: .failed(reason: "codec error"))
        let coordinator = VideoExportCoordinator(exporter: fake)

        let outcome = await coordinator.run(
            sourceLocalIdentifier: "vid1",
            preset: .highQuality,
            cancellation: CancellationToken()
        )

        XCTAssertEqual(outcome, .failed(reason: "codec error"))
    }
}
