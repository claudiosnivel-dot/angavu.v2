import XCTest
@testable import AngavuDomain

// T-071 — AC-071-1 / AC-071-2. Aesthetics come progressive enhancement iOS 18.
// Domain puro: nitidezza e aesthetics reali sono dietro i port, qui fake. L'oracolo
// gira senza device.

/// Fake scorer di nitidezza (id → Double?).
private struct FakeSharpnessScorer: SharpnessScoring {
    let values: [String: Double?]
    func sharpness(for asset: LibraryAsset) throws -> Double? { values[asset.id].flatMap { $0 } }
}

/// Fake scorer di aesthetics (id → Double?). Un `nil` simula iOS 17 (nessun termine estetico).
private struct FakeAestheticsScorer: AestheticsScoring {
    let values: [String: Double?]
    func aesthetics(for asset: LibraryAsset) throws -> Double? { values[asset.id].flatMap { $0 } }
}

final class AestheticsEnhancementTests: XCTestCase {

    private func photo(_ id: String) -> LibraryAsset {
        LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 4032, height: 3024),
            creationDate: nil,
            subtypes: []
        )
    }

    // AC-071-1: con aesthetics disponibile (iOS 18), il punteggio combinato include il
    // termine estetico oltre alla nitidezza, ed è marcato come "usa aesthetics".
    func test_withAestheticsCombinedIncludesTheAestheticTerm() throws {
        let sharpness = FakeSharpnessScorer(values: ["p": 0.6])
        let aesthetics = FakeAestheticsScorer(values: ["p": 0.3])

        let score = try XCTUnwrap(
            try BlurAssessment.assess(photo("p"), sharpnessScoring: sharpness, aestheticsScoring: aesthetics)
        )

        XCTAssertTrue(score.usesAesthetics)
        XCTAssertEqual(score.aesthetics, 0.3)
        // Il combinato include il termine aesthetics: 0.6 + 0.3.
        XCTAssertEqual(score.combined, 0.9, accuracy: 1e-9)
        // …ed è strettamente maggiore della sola nitidezza (il termine ha concorso).
        XCTAssertGreaterThan(score.combined, score.sharpness)
    }

    // AC-071-2: su iOS 17 (aesthetics nil) il punteggio usa la sola nitidezza, è
    // marcato "senza aesthetics" e NON fallisce.
    func test_withoutAestheticsDegradesToSharpnessOnlyMarkedAndDoesNotFail() throws {
        let sharpness = FakeSharpnessScorer(values: ["p": 0.6])
        let aesthetics = FakeAestheticsScorer(values: ["p": Double?.none])

        let score = try XCTUnwrap(
            try BlurAssessment.assess(photo("p"), sharpnessScoring: sharpness, aestheticsScoring: aesthetics)
        )

        XCTAssertFalse(score.usesAesthetics)          // marcato "senza aesthetics"
        XCTAssertNil(score.aesthetics)
        XCTAssertEqual(score.combined, 0.6, accuracy: 1e-9)   // sola nitidezza
    }

    // Senza nitidezza calcolabile (nil) non c'è assessment: coerente con T-070
    // (mai un punteggio inventato su un asset non verificabile).
    func test_assessReturnsNilWhenSharpnessUncomputable() throws {
        let sharpness = FakeSharpnessScorer(values: ["p": Double?.none])
        let aesthetics = FakeAestheticsScorer(values: ["p": 0.9])

        let score = try BlurAssessment.assess(
            photo("p"),
            sharpnessScoring: sharpness,
            aestheticsScoring: aesthetics
        )
        XCTAssertNil(score)
    }

    // Il costruttore puro da valori marca coerentemente la presenza/assenza del termine.
    func test_pureScoreConstructorMarksAestheticsPresence() {
        XCTAssertTrue(BlurAssessment.score(sharpness: 0.5, aesthetics: 0.2).usesAesthetics)
        XCTAssertFalse(BlurAssessment.score(sharpness: 0.5, aesthetics: nil).usesAesthetics)
    }
}
