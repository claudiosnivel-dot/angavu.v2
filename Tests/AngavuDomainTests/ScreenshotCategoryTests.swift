import XCTest
@testable import AngavuDomain

// T-061 — AC-061-1 / AC-061-2. Categorie in blocco: screenshot dal subtype
// indicizzato, screen recording dall'euristica dichiarata. Domain puro.

final class ScreenshotCategoryTests: XCTestCase {

    private func photo(
        _ id: String,
        pixels: PixelSize = PixelSize(width: 4032, height: 3024),
        subtypes: Set<AssetSubtype> = []
    ) -> LibraryAsset {
        LibraryAsset(id: id, kind: .photo, pixelSize: pixels, creationDate: nil, subtypes: subtypes)
    }

    private func video(_ id: String, pixels: PixelSize) -> LibraryAsset {
        LibraryAsset(id: id, kind: .video, pixelSize: pixels, creationDate: nil, subtypes: [])
    }

    // AC-061-1: la categoria screenshot contiene esattamente gli asset marcati
    // screenshot dal subtype, nessun altro.
    func test_screenshotsAreExactlyThoseWithScreenshotSubtype() {
        let assets = [
            photo("shot-1", subtypes: [.screenshot]),
            photo("normal", subtypes: []),
            photo("live", subtypes: [.livePhoto]),
            photo("shot-2", subtypes: [.screenshot, .livePhoto]),
            video("clip", pixels: PixelSize(width: 1920, height: 1080))
        ]

        let screenshots = ScreenshotCategory.screenshots(assets)

        XCTAssertEqual(screenshots.map(\.id), ["shot-1", "shot-2"])
    }

    // Nessuno screenshot presente → categoria vuota.
    func test_noScreenshotYieldsEmptyCategory() {
        let assets = [photo("a"), photo("b", subtypes: [.livePhoto])]
        XCTAssertTrue(ScreenshotCategory.screenshots(assets).isEmpty)
    }

    // AC-061-2: la categoria screen recording contiene solo i video che
    // soddisfano l'euristica dichiarata (dimensioni pixel == risoluzione schermo
    // nota, orientamento a parte).
    func test_screenRecordingsMatchDeclaredHeuristicOnly() {
        // Risoluzioni schermo note (es. iPhone 14 Pro: 1179x2556).
        let heuristic = ScreenRecordingHeuristic(screenPixelSizes: [
            PixelSize(width: 1179, height: 2556),
            PixelSize(width: 1170, height: 2532)
        ])
        let assets = [
            video("rec-portrait", pixels: PixelSize(width: 1179, height: 2556)),  // ✓ combacia
            video("rec-landscape", pixels: PixelSize(width: 2532, height: 1170)), // ✓ combacia (ruotato)
            video("camera-1080p", pixels: PixelSize(width: 1920, height: 1080)),  // ✗ non è risoluzione schermo
            // ✗ una foto con la forma di uno schermo: l'euristica esige `kind == .video`.
            photo("screenshot-shaped", pixels: PixelSize(width: 1179, height: 2556), subtypes: [.screenshot])
        ]

        let recordings = ScreenshotCategory.screenRecordings(assets, heuristic: heuristic)

        XCTAssertEqual(recordings.map(\.id), ["rec-portrait", "rec-landscape"])
    }

    // Un'euristica senza risoluzioni note non marca nulla (nessun falso positivo).
    func test_emptyHeuristicMatchesNoScreenRecording() {
        let heuristic = ScreenRecordingHeuristic(screenPixelSizes: [])
        let assets = [video("clip", pixels: PixelSize(width: 1179, height: 2556))]
        XCTAssertTrue(ScreenshotCategory.screenRecordings(assets, heuristic: heuristic).isEmpty)
    }
}
