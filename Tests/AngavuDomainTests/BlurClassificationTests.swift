import XCTest
@testable import AngavuDomain

// T-070 — AC-070-1 / AC-070-2. Classificazione sfocato/non-sfocato per soglia.
// Domain puro: lo scoring reale (Core Image/vImage) è dietro il port e qui
// sostituito da un fake. L'oracolo gira senza device.

/// Fake scorer: mappa l'`id` dell'asset a una nitidezza scelta dal test (o `nil`
/// per "non calcolabile on-device").
private struct FakeSharpnessScorer: SharpnessScoring {
    let values: [String: Double?]

    func sharpness(for asset: LibraryAsset) throws -> Double? {
        // `values[id]` è `Double??`: la chiave assente e il `nil` esplicito collassano
        // entrambi su "non calcolabile" (flatMap appiattisce il doppio optional).
        values[asset.id].flatMap { $0 }
    }
}

final class BlurClassificationTests: XCTestCase {

    private func photo(_ id: String) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 4032, height: 3024),
            creationDate: nil,
            subtypes: []
        )
    }

    private func video(_ id: String) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: .video,
            pixelSize: PixelSize(width: 1920, height: 1080),
            creationDate: nil,
            subtypes: []
        )
    }

    private let threshold = BlurThreshold(minimumSharpness: 0.30)

    // AC-070-1: sotto soglia → blurry; sopra soglia → non blurry.
    func test_belowThresholdIsBlurryAboveIsNot() throws {
        let scorer = FakeSharpnessScorer(values: [
            "sharp": 0.80,   // sopra 0.30 → non sfocato
            "blurry": 0.10   // sotto 0.30 → sfocato
        ])

        XCTAssertFalse(try BlurClassification.isBlurry(photo("sharp"), scoring: scorer, threshold: threshold))
        XCTAssertTrue(try BlurClassification.isBlurry(photo("blurry"), scoring: scorer, threshold: threshold))
    }

    // AC-070-2: esattamente ALLA soglia → NON blurry (regola di confine dichiarata:
    // sfocato sse e solo se STRETTAMENTE sotto soglia).
    func test_exactlyAtThresholdIsNotBlurry_declaredBoundaryRule() {
        XCTAssertFalse(BlurClassification.isBlurry(sharpness: 0.30, threshold: threshold))
        // Un capello sotto la soglia è invece sfocato: il confine è netto e deterministico.
        XCTAssertTrue(BlurClassification.isBlurry(sharpness: 0.30 - 1e-9, threshold: threshold))
    }

    // Nitidezza non calcolabile (nil) → mai flaggato come sfocato: nessun falso
    // positivo su un asset non verificabile.
    func test_unmeasurableSharpnessIsNeverBlurry() throws {
        let scorer = FakeSharpnessScorer(values: ["unknown": Double?.none])
        XCTAssertFalse(try BlurClassification.isBlurry(photo("unknown"), scoring: scorer, threshold: threshold))
        XCTAssertFalse(BlurClassification.isBlurry(sharpness: nil, threshold: threshold))
    }

    // Il batch seleziona i soli sfocati, escludendo i video (la sfocatura fotografica
    // non è definita per i video) e preservando l'ordine d'ingresso.
    func test_batchSelectsBlurryPhotosOnly() {
        let assets = [photo("a"), video("v"), photo("b"), photo("c")]
        let scorer = FakeSharpnessScorer(values: [
            "a": 0.05,   // sfocata
            "v": 0.01,   // video: escluso a prescindere dal valore
            "b": 0.90,   // nitida
            "c": 0.20    // sfocata
        ])

        let outcome = BlurClassification.blurry(
            among: assets,
            scoring: scorer,
            threshold: threshold,
            cancellation: CancellationToken()
        )

        guard case let .completed(blurry) = outcome else {
            return XCTFail("atteso esito completed, ottenuto \(outcome)")
        }
        XCTAssertEqual(blurry.map(\.id), ["a", "c"])
    }

    // La cancellazione al confine di un blocco lascia i candidati residui non
    // processati e riporta il progresso (motore T-004).
    func test_batchCancellationLeavesResidualsUnprocessed() {
        let assets = (0..<10).map { photo("p\($0)") }
        var values: [String: Double?] = [:]
        for index in 0..<10 { values["p\(index)"] = 0.01 } // tutte sfocate
        let scorer = FakeSharpnessScorer(values: values)

        let token = CancellationToken()
        token.cancel()   // cancellato prima ancora del primo blocco

        let outcome = BlurClassification.blurry(
            among: assets,
            scoring: scorer,
            threshold: threshold,
            chunkSize: 4,
            cancellation: token
        )

        guard case let .cancelled(progress) = outcome else {
            return XCTFail("atteso esito cancelled, ottenuto \(outcome)")
        }
        XCTAssertEqual(progress.processed, 0)
        XCTAssertEqual(progress.total, 10)
    }
}
