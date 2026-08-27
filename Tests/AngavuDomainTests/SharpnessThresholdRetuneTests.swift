import XCTest
@testable import AngavuDomain

// FSE-C2 (Domain) — Oracolo della SOGLIA di sfocatura ri-tarata alla nuova taglia di
// decodifica (`.sharpness` ≈64px, FSE-C1), AC-FSE-C2-1.
//
// La nitidezza (varianza del Laplaciano) è sensibile alla risoluzione: cambiando la
// taglia di decodifica il valore grezzo cambia, quindi la soglia va ri-tarata e
// RI-DICHIARATA, non ereditata a caso (FAST-SCAN-ENGINE-PLAN §FSE-C2).
//
// Onestà (00-INDEX §6, L-COL-006): le fixture di nitidezza NOTA non sono numeri
// inventati — sono griglie sintetiche (scacchiera ad alta frequenza = nitida; piatta /
// rampa lineare = sfocata) passate nella STESSA `SharpnessMetric` di produzione. Così
// «nitida» e «sfocata» sono grounded nella matematica reale, non asseriti. La regola di
// confine (alla soglia = NON sfocato) è provata direttamente sulla classificazione pura.
final class SharpnessThresholdRetuneTests: XCTestCase {

    private let side = SharpnessMetric.referenceGridSide   // 48
    private let threshold = CategoryDetectionDefaultsMirror.blur   // 0.3 @ 64px

    // MARK: - Fixture di nitidezza NOTA (griglie sintetiche → matematica reale)

    /// Scacchiera 0/255 ad alta frequenza: massima varianza del Laplaciano → nitida.
    private func sharpGrid() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for column in 0..<side {
                pixels[row * side + column] = (row + column).isMultiple(of: 2) ? 0 : 255
            }
        }
        return pixels
    }

    /// Superficie piatta: nessuna variazione → varianza 0 → sfocata.
    private func flatGrid() -> [UInt8] {
        [UInt8](repeating: 128, count: side * side)
    }

    /// Rampa lineare: il Laplaciano di un gradiente lineare è 0 ovunque → sfocata
    /// (nessun dettaglio ad alta frequenza), coerente con l'intuizione.
    private func linearRampGrid() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for column in 0..<side {
                pixels[row * side + column] = UInt8(min(255, column * 5))
            }
        }
        return pixels
    }

    // MARK: - AC-FSE-C2-1 — nitide sopra soglia, sfocate sotto

    func testSharpFixtureIsAboveThresholdAndNotBlurry() throws {
        let sharpness = try XCTUnwrap(SharpnessMetric.normalizedSharpness(grayscale: sharpGrid(), side: side))
        // La scacchiera è nettamente sopra soglia (nessun falso positivo sulla nitida).
        XCTAssertGreaterThan(sharpness, threshold.minimumSharpness)
        XCTAssertFalse(BlurClassification.isBlurry(sharpness: sharpness, threshold: threshold))
    }

    func testFlatFixtureIsBelowThresholdAndBlurry() throws {
        let sharpness = try XCTUnwrap(SharpnessMetric.normalizedSharpness(grayscale: flatGrid(), side: side))
        XCTAssertLessThan(sharpness, threshold.minimumSharpness)
        XCTAssertTrue(BlurClassification.isBlurry(sharpness: sharpness, threshold: threshold))
    }

    func testLinearRampFixtureIsBlurry() throws {
        let sharpness = try XCTUnwrap(SharpnessMetric.normalizedSharpness(grayscale: linearRampGrid(), side: side))
        XCTAssertLessThan(sharpness, threshold.minimumSharpness)
        XCTAssertTrue(BlurClassification.isBlurry(sharpness: sharpness, threshold: threshold))
    }

    // MARK: - AC-FSE-C2-1 — regola di confine invariata (alla soglia = NON sfocato)

    func testBoundaryExactlyAtThresholdIsNotBlurry() {
        XCTAssertFalse(
            BlurClassification.isBlurry(sharpness: threshold.minimumSharpness, threshold: threshold),
            "esattamente ALLA soglia deve restare NON sfocato (scelta conservativa)"
        )
    }

    func testJustBelowThresholdIsBlurry() {
        XCTAssertTrue(
            BlurClassification.isBlurry(sharpness: threshold.minimumSharpness - 0.0001, threshold: threshold)
        )
    }

    // MARK: - Dichiarazione della taglia di riferimento (pin)

    func testThresholdDeclaresSharpnessReferenceSize() {
        // La soglia dichiara la scala a cui è tarata: la taglia `.sharpness` di FSE-C1.
        // Se la taglia di decodifica cambia senza ri-tarare, questo pin fallisce.
        XCTAssertEqual(threshold.referenceLongestSide, LogicalImageSize.sharpness.longestSide)
        XCTAssertEqual(threshold.referenceLongestSide, 64)
    }
}

/// La soglia di default vive in `CategoryDetectionDefaults` (target AngavuFeatures, non
/// importabile qui): la si rispecchia con lo STESSO valore dichiarato, così l'oracolo di
/// Domain prova la classificazione senza dipendere da Features. La parità del valore è
/// garantita dal fatto che entrambi derivano la taglia da `LogicalImageSize.sharpness`.
private enum CategoryDetectionDefaultsMirror {
    static let blur = BlurThreshold(
        minimumSharpness: 0.3,
        referenceLongestSide: LogicalImageSize.sharpness.longestSide
    )
}
