import XCTest
@testable import AngavuDomain

// T-100 — AC-100-1 / AC-100-2. Il contenuto del manifesto e dei non-goals come
// dati testabili, coerenti col VISION-AND-CONSTRAINTS §4.

final class ManifestContentTests: XCTestCase {

    // AC-100-1: elencando i non-goals, sono incluse — per nome stabile — almeno
    // "niente cache di sistema", "no ads" e "zero backend".
    func test_nonGoalsIncludeCardinalRenunciations() {
        let content = ManifestContent.angavu

        let required: Set<NonGoalID> = [.systemCacheCleaning, .noAds, .zeroBackend]
        XCTAssertTrue(
            content.nonGoalIDs.isSuperset(of: required),
            "i non-goals devono includere cache di sistema, no ads e zero backend"
        )
    }

    // AC-100-1 (rinforzo): ogni non-goal ha testo e motivazione non vuoti —
    // niente voce fantasma senza contenuto per l'utente.
    func test_everyNonGoalHasTextAndRationale() {
        for goal in ManifestContent.angavu.nonGoals {
            XCTAssertFalse(goal.text.isEmpty, "\(goal.id) senza testo")
            XCTAssertFalse(goal.rationale.isEmpty, "\(goal.id) senza motivazione")
        }
    }

    // AC-100-2: nessuna voce di non-goal promette una capacità (è una rinuncia),
    // e ogni promessa positiva è mantenibile on-device → nessun claim impossibile
    // nel sandbox iOS (coerenza col manifesto).
    func test_noImpossibleCapabilityIsPromised() {
        let content = ManifestContent.angavu

        XCTAssertFalse(
            content.anyNonGoalClaimsCapability,
            "un non-goal è una rinuncia, mai la promessa di una capacità"
        )
        XCTAssertTrue(
            content.allPromisesAchievableOnDevice,
            "si promette solo ciò che iOS permette on-device, senza backend"
        )
    }

    // AC-100-2 (guardia): se il contenuto contenesse un non-goal formulato come
    // capacità, l'invariante lo intercetterebbe — l'oracolo non è vacuo.
    func test_capabilityClaimIsDetected() {
        let content = ManifestContent(
            headline: "x",
            promises: [ManifestPromise(id: .offline, text: "ok")],
            nonGoals: [
                NonGoal(
                    id: .systemCacheCleaning,
                    text: "Puliamo la cache di sistema!",
                    rationale: "—",
                    claimsCapability: true
                )
            ]
        )
        XCTAssertTrue(content.anyNonGoalClaimsCapability)
    }

    // Guardia sul versante promesse: una promessa non mantenibile on-device
    // rompe l'invariante (nessun verde vacuo).
    func test_offDevicePromiseIsDetected() {
        let content = ManifestContent(
            headline: "x",
            promises: [ManifestPromise(id: .realNumbers, text: "sync cloud", achievableOnDevice: false)],
            nonGoals: []
        )
        XCTAssertFalse(content.allPromisesAchievableOnDevice)
    }
}
