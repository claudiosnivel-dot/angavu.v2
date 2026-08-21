// AngavuData — adatta la piattaforma (PhotoKit/Vision/AVFoundation, in arrivo nei
// macrotask successivi) al Domain puro. Dipende SOLO da AngavuDomain (verso il basso).
// In `foundation` è un segnaposto cross-platform: nessun framework di device ancora.
import AngavuDomain

/// Marcatore di modulo per i test di struttura (AC-001-1).
public enum AngavuData {
    public static let moduleName = "AngavuData"
    /// Prova la direzione consentita della dipendenza: Data può vedere il Domain.
    public static let domainSeen = AngavuDomain.moduleName
}
