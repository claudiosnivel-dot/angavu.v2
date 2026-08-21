// AngavuFeatures — presentazione (SwiftUI, in arrivo nei macrotask successivi).
// Dipende da AngavuDomain e AngavuData (verso il basso). In `foundation` è un
// segnaposto cross-platform: nessun import di SwiftUI ancora.
import AngavuDomain
import AngavuData

/// Marcatore di modulo per i test di struttura (AC-001-1).
public enum AngavuFeatures {
    public static let moduleName = "AngavuFeatures"
    /// Prova le direzioni consentite: Features vede sia Domain sia Data.
    public static let dependenciesSeen = [AngavuDomain.moduleName, AngavuData.moduleName]
}
