import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-117 — AC-117-1 / AC-117-2. L'euristica screen-recording consuma le risoluzioni
// del provider (non valori hardcoded).

private struct StubResolutions: ScreenResolutionProviding {
    let sizes: [PixelSize]
    func screenPixelSizes() -> [PixelSize] { sizes }
}

private func video(_ id: String, _ width: Int, _ height: Int) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .video,
        pixelSize: PixelSize(width: width, height: height),
        creationDate: nil,
        subtypes: []
    )
}

final class ScreenResolutionProviderTests: XCTestCase {

    // AC-117-1: provider con la risoluzione del device + video a quella risoluzione
    // → classificato come screen recording (orientamento a parte).
    func test_videoAtDeviceResolutionIsScreenRecording() {
        let provider = StubResolutions(sizes: [PixelSize(width: 1170, height: 2532)])
        // Stessa risoluzione, orientamento landscape: deve comunque combaciare.
        let assets = [video("REC", 2532, 1170)]

        let recordings = ScreenRecordingHeuristicFactory.screenRecordings(among: assets, provider: provider)

        XCTAssertEqual(recordings.map(\.id), ["REC"])
    }

    // AC-117-2: video a una risoluzione che non combacia con nessuno schermo noto
    // → NON è screen recording.
    func test_videoAtUnknownResolutionIsNotScreenRecording() {
        let provider = StubResolutions(sizes: [PixelSize(width: 1170, height: 2532)])
        let assets = [video("OTHER", 640, 480)]

        let recordings = ScreenRecordingHeuristicFactory.screenRecordings(among: assets, provider: provider)

        XCTAssertTrue(recordings.isEmpty)
    }

    // La factory alimenta l'euristica con le risoluzioni del provider.
    func test_factoryFeedsHeuristicFromProvider() {
        let provider = StubResolutions(sizes: [PixelSize(width: 828, height: 1792)])
        let heuristic = ScreenRecordingHeuristicFactory.make(from: provider)
        XCTAssertTrue(heuristic.matches(video("R", 828, 1792)))
        XCTAssertFalse(heuristic.matches(video("R", 100, 100)))
    }

    // Il provider di default espone risoluzioni note non vuote (guardia non vacua).
    func test_defaultProviderExposesKnownResolutions() {
        let provider = KnownDeviceScreenResolutions()
        let sizes = provider.screenPixelSizes()
        XCTAssertFalse(sizes.isEmpty)
        // Una risoluzione iPhone diffusa è presente: un video a quella misura combacia.
        let heuristic = ScreenRecordingHeuristicFactory.make(from: provider)
        XCTAssertTrue(heuristic.matches(video("R", 1170, 2532)))
    }
}
