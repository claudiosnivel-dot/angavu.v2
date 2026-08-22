import XCTest
@testable import AngavuDomain

// T-080 — AC-080-1 / AC-080-2. Stima marcata + gate opt-in.

final class CompressionOptInTests: XCTestCase {

    // AC-080-1: il risparmio stimato è SEMPRE 'estimated', mai esatto/garantito.
    func test_saving_isAlwaysEstimated() {
        let spec = VideoSpec(
            originalBytes: 200_000_000,           // 200 MB
            durationSeconds: 120,
            sourceBitrateBitsPerSec: 12_000_000   // 12 Mbps
        )
        let saving = CompressionEstimator.estimatedSaving(for: spec, preset: .balanced)

        XCTAssertFalse(saving.isExact, "il risparmio non va mai spacciato per esatto")
        if case .estimated(let bytes) = saving {
            XCTAssertGreaterThan(bytes, 0, "con questo bitrate/durata la stima è un risparmio positivo")
        } else {
            XCTFail("atteso ByteSize.estimated, ottenuto \(saving)")
        }
    }

    // Se la ricodifica non porta vantaggio, il risparmio stimato è 0 (mai negativo).
    func test_saving_neverNegative() {
        let spec = VideoSpec(originalBytes: 1_000, durationSeconds: 60, sourceBitrateBitsPerSec: 50_000_000)
        let saving = CompressionEstimator.estimatedSaving(for: spec, preset: .highQuality)
        XCTAssertEqual(saving.bytes, 0)
        XCTAssertFalse(saving.isExact)
    }

    // AC-080-2: senza consenso opt-in l'avvio è rifiutato; col consenso è permesso.
    func test_optIn_blocksStartUntilConsent() {
        var optIn = CompressionOptIn()
        let batch = ["v1", "v2"]

        XCTAssertFalse(optIn.canStart(batch), "senza consenso l'avvio è rifiutato")

        XCTAssertTrue(optIn.grantConsent(for: batch))
        XCTAssertTrue(optIn.canStart(batch), "col consenso sul batch l'avvio è permesso")
    }

    // Il consenso copre solo gli id concessi: un id fuori dal batch resta bloccato.
    func test_optIn_consentIsScopedToGrantedIds() {
        var optIn = CompressionOptIn()
        XCTAssertTrue(optIn.grantConsent(for: ["v1"]))

        XCTAssertTrue(optIn.canStart(["v1"]))
        XCTAssertFalse(optIn.canStart(["v1", "v2"]), "v2 non è coperto dal consenso")
        XCTAssertFalse(optIn.grantConsent(for: []), "un batch vuoto non è un consenso")
    }
}
