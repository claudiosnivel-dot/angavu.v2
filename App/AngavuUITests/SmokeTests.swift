import XCTest

// FSE-J0 — Harness di verifica del cablaggio, LIVELLO B (job Simulatore `ios-uitest`).
//
// A differenza del Livello A (che testa la radice di composizione + i seam in-process),
// il Livello B ESEGUE l'app su un Simulatore CONCRETO in CI: `xcodebuild test` lancia il
// binario, e `xcrun simctl addmedia` semina foto di fixture nella libreria PRIMA del test.
// Questo è ciò che permette a FSE-J1 di verificare l'ELIMINAZIONE REALE (le foto vanno in
// «Eliminati di recente») e a C6 il ciclo di vita — senza il device dell'utente.
//
// Questo primo test è di FUMO: prova solo che l'app si avvia e mostra la schermata
// iniziale. È l'esempio verde che abilita il Livello B; i test end-to-end vivono nei
// task FSE-J1… che riusano questo target.
final class SmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // AC-FSE-J0-2: l'app si avvia e la CI ora ESEGUE l'app (non la sola compilazione).
    // Su un Simulatore appena creato (UserDefaults pulite) il primo avvio mostra
    // l'onboarding-manifesto: il wordmark "Angavu" (brand DI-005, stabile) prova che
    // l'app è viva. Fallback sul bottone "Inizia" per robustezza. FSE-K3: se un test
    // precedente dello stesso run ha già scansionato (`RelaunchCategoryCacheUITests`),
    // il lancio RIPRISTINA e atterra in dashboard («Numeri veri»): anche quella è la
    // schermata iniziale legittima di un'app viva.
    func test_appLaunches_showsInitialScreen() {
        let app = XCUIApplication()
        app.launch()

        let wordmark = app.staticTexts["Angavu"]
        let startButton = app.buttons["Inizia"]
        let restoredDashboard = app.navigationBars["Numeri veri"]
        let appeared = wordmark.waitForExistence(timeout: 30)
            || startButton.waitForExistence(timeout: 5)
            || restoredDashboard.waitForExistence(timeout: 5)

        XCTAssertTrue(appeared, "l'app deve avviarsi e mostrare la schermata iniziale (onboarding/Home/dashboard)")
    }
}
