import XCTest

// FSE-K3 — LIVELLO B: il caso MAI coperto dal gate — il COLD RELAUNCH.
//
// Diagnosi (2026-09-01): i risultati delle categorie vivevano solo in memoria e il
// ripristino al lancio salta la scansione → dopo ogni terminazione dell'app (iOS la
// termina spesso per memoria) lo store era vuoto e ogni categoria pesante rigirava il
// rilevatore. La CI non faceva mai un relaunch → dichiarava verdi i fix precedenti.
//
// Questo test ESEGUE l'app sul Simulatore (job `ios-uitest`, foto seminate via
// `simctl addmedia` — DUE copie identiche del fixture → un duplicato esatto reale):
//   scansione completa → apertura di «Duplicati esatti» → TERMINAZIONE dell'app →
//   rilancio → apertura della stessa categoria.
// Prova (AC-FSE-K3-3): dopo il rilancio la categoria è servita DALLA CACHE idratata
// (identificatore `category.review.loaded.cache`, esposto dalla View SOLO sul cache hit,
// che per costruzione non invoca il rilevatore), non dal rilevatore
// (`…loaded.detector`), senza spinner «Analisi della categoria…», e con lo STESSO
// conteggio del primo lancio. Onestà (L-COL-006): il «0 rilevatori» è osservato dal
// percorso di caricamento della View (cache vs detector), non da un contatore in-process.

final class RelaunchCategoryCacheUITests: XCTestCase {

    private let categoryTitle = "Duplicati esatti"
    private let cacheIdentifier = "category.review.loaded.cache"
    private let detectorIdentifier = "category.review.loaded.detector"
    private let spinnerLabel = "Analisi della categoria…"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_scanThenColdRelaunch_opensCategoryFromCacheWithoutDetector() {
        let app = XCUIApplication()
        app.launch()
        finishOnboardingIfPresented(app)

        // Home → scansione completa (permesso foto concesso dal CI o dall'alert di sistema).
        startScan(app)
        allowPhotoAccessIfAsked()
        goToDashboardAfterScan(app)

        // Primo lancio: apri la categoria e leggi il conteggio mostrato.
        openCategory(app)
        let firstLoaded = waitForLoadedContent(app, timeout: 60)
        let firstValue = firstLoaded.label

        // COLD RELAUNCH: terminazione forzata + rilancio. Il ripristino (FSE-I1 + K3)
        // idrata lo store e atterra da solo in dashboard.
        app.terminate()
        app.launch()

        openCategory(app)
        let relaunched = app.descendants(matching: .any).matching(identifier: cacheIdentifier).firstMatch
        XCTAssertTrue(
            relaunched.waitForExistence(timeout: 15),
            "dopo il cold relaunch la categoria deve essere servita dalla cache idratata (0 rilevatori)"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: detectorIdentifier).firstMatch.exists,
            "il rilevatore NON deve essere rigirato all'ingresso della categoria"
        )
        XCTAssertFalse(app.staticTexts[spinnerLabel].exists, "nessuno spinner di ricalcolo")
        XCTAssertEqual(relaunched.label, firstValue, "stesso risultato del primo lancio (keep/removable identici)")
    }

    // MARK: - Passi

    private func finishOnboardingIfPresented(_ app: XCUIApplication) {
        let start = app.buttons["Inizia"]
        if start.waitForExistence(timeout: 15) { start.tap() }
    }

    private func startScan(_ app: XCUIApplication) {
        let scan = app.buttons["Analizza la libreria"]
        if !scan.waitForExistence(timeout: 30) {
            // Stato residuo di un run precedente (dashboard ripristinata): torna in Home.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(scan.waitForExistence(timeout: 30), "la Home deve mostrare il tasto di scansione")
        scan.tap()
    }

    /// Alert di sistema del permesso foto (Springboard): concede l'accesso completo se
    /// compare; se il CI l'ha già concesso (`simctl privacy`) non compare e si prosegue.
    private func allowPhotoAccessIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 10) else { return }
        let preferred = [
            "Allow Full Access", "Allow Access to All Photos",
            "Consenti l'accesso completo", "Consenti l'accesso a tutte le foto"
        ]
        for title in preferred where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return
        }
        let predicate = NSPredicate(format: "label BEGINSWITH[c] 'Allow' OR label BEGINSWITH[c] 'Consenti'")
        let fallback = alert.buttons.matching(predicate).firstMatch
        if fallback.exists { fallback.tap() }
    }

    private func goToDashboardAfterScan(_ app: XCUIApplication) {
        let full = app.buttons["È ora di fare pulizia!"]
        let limited = app.buttons["Vedi i numeri veri"]
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            if full.exists { full.tap(); return }
            if limited.exists { limited.tap(); return }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTFail("la scansione deve completarsi e offrire l'accesso alla dashboard")
    }

    /// Dashboard («Numeri veri») → riga «Duplicati esatti», scorrendo se è sotto la piega.
    private func openCategory(_ app: XCUIApplication) {
        let link = app.staticTexts[categoryTitle]
        XCTAssertTrue(link.waitForExistence(timeout: 60), "la dashboard deve elencare le categorie")
        var swipes = 0
        while !link.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        link.tap()
    }

    /// Contenuto caricato della categoria (cache o rilevatore), qualunque sia la provenienza.
    private func waitForLoadedContent(_ app: XCUIApplication, timeout: TimeInterval) -> XCUIElement {
        let anyLoaded = NSPredicate(format: "identifier == %@ OR identifier == %@", cacheIdentifier, detectorIdentifier)
        let element = app.descendants(matching: .any).matching(anyLoaded).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "la categoria deve caricare il suo contenuto")
        return element
    }
}
