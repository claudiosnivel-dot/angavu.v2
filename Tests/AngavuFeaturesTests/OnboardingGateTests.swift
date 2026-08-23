import XCTest
@testable import AngavuFeatures

// R-00 — Persistenza dell'onboarding. La transizione onboarding→home è View-level
// (compilata in CI, resa non coperta); qui si prova l'ORACOLO puro della scelta
// "mostrare l'onboarding?" e la stabilità della chiave di persistenza, così il
// bug (ricomparsa a ogni avvio) resta coperto da un test e non da un'impressione.

final class OnboardingGateTests: XCTestCase {

    // Non ancora completato → l'onboarding va mostrato.
    func test_shouldPresent_whenNotYetFinished() {
        XCTAssertTrue(OnboardingGate.shouldPresentOnboarding(hasFinishedOnboarding: false))
    }

    // Già completato (persistito) → l'onboarding NON ricompare.
    func test_shouldNotPresent_whenAlreadyFinished() {
        XCTAssertFalse(OnboardingGate.shouldPresentOnboarding(hasFinishedOnboarding: true))
    }

    // La chiave di persistenza è stabile e non vuota: `@AppStorage` e i test la
    // condividono. Se cambia, un utente esistente rivedrebbe l'onboarding.
    func test_storageKey_isStableAndNonEmpty() {
        XCTAssertEqual(OnboardingGate.didFinishStorageKey, "didFinishOnboarding")
        XCTAssertFalse(OnboardingGate.didFinishStorageKey.isEmpty)
    }
}
