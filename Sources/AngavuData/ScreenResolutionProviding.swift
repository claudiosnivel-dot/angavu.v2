import AngavuDomain

// T-117 (wiring) — Risoluzioni schermo del device per l'euristica screen-recording.
//
// L'euristica di large_old_media (T-061) classifica come screen recording i video
// le cui dimensioni coincidono con una risoluzione schermo NOTA. Finora le
// risoluzioni erano iniettate nei test; qui un provider le fornisce a runtime.
//
// Scelta dichiarata (L-COL-006): il provider di default espone una tabella di
// risoluzioni schermo native NOTE dei device iOS, non `UIScreen.main` — che è
// deprecata su iOS 16+ (dipende dalla window scene) e romperebbe la build sotto
// `-warnings-as-errors`. Una screen recording è per costruzione alla risoluzione
// dello schermo del device, che è una di quelle note: la tabella è quindi una base
// onesta e robusta, raffinabile con la risoluzione esatta della scena quando una
// View la fornisce.

/// Port: espone le risoluzioni schermo note (in pixel) rilevanti all'euristica.
public protocol ScreenResolutionProviding {
    /// Risoluzioni schermo note, in pixel nativi. L'orientamento è irrilevante:
    /// l'euristica confronta i lati come insieme non ordinato.
    func screenPixelSizes() -> [PixelSize]
}

/// Provider di default basato su una tabella di risoluzioni native NOTE dei device
/// iOS. Puro (nessuna API di piattaforma), quindi deterministico e testabile.
public struct KnownDeviceScreenResolutions: ScreenResolutionProviding {
    public init() {}

    public func screenPixelSizes() -> [PixelSize] { Self.known }

    /// Risoluzioni native (pixel) di device iOS diffusi. Non esaustiva; ampliabile.
    static let known: [PixelSize] = [
        PixelSize(width: 750, height: 1334),   // iPhone SE (2/3ª gen), 8
        PixelSize(width: 828, height: 1792),   // iPhone XR, 11
        PixelSize(width: 1080, height: 1920),  // iPhone 6/7/8 Plus (downsampled)
        PixelSize(width: 1125, height: 2436),  // iPhone X, XS, 11 Pro
        PixelSize(width: 1170, height: 2532),  // iPhone 12/13/14, 12/13 Pro
        PixelSize(width: 1179, height: 2556),  // iPhone 15/16, 14 Pro
        PixelSize(width: 1284, height: 2778),  // iPhone 12/13 Pro Max, 14 Plus
        PixelSize(width: 1290, height: 2796),  // iPhone 14 Pro Max, 15/16 Plus, Pro Max
        PixelSize(width: 1640, height: 2360),  // iPad Air (10.9")
        PixelSize(width: 2048, height: 2732)   // iPad Pro 12.9"
    ]
}
