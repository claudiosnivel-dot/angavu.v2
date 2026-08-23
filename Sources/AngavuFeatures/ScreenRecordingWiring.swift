import AngavuDomain
import AngavuData

// T-117 (wiring) — Cablaggio dell'euristica screen-recording al provider di
// risoluzioni. La seam vive in Features (altitudine: il Domain resta puro, non
// conosce il provider del Data; qui li si compone).

/// Costruisce l'euristica screen-recording (T-061) dalle risoluzioni schermo
/// fornite dal provider, invece che da valori hardcoded.
public enum ScreenRecordingHeuristicFactory {
    /// Euristica alimentata dalle risoluzioni note del provider.
    public static func make(from provider: any ScreenResolutionProviding) -> ScreenRecordingHeuristic {
        ScreenRecordingHeuristic(screenPixelSizes: provider.screenPixelSizes())
    }

    /// Comodità: le screen recording fra gli asset dati, usando l'euristica
    /// alimentata dal provider (delega a `ScreenshotCategory.screenRecordings`).
    public static func screenRecordings(
        among assets: [LibraryAsset],
        provider: any ScreenResolutionProviding
    ) -> [LibraryAsset] {
        ScreenshotCategory.screenRecordings(assets, heuristic: make(from: provider))
    }
}
