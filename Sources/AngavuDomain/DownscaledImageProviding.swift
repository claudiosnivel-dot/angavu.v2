import Foundation

// FSE-C1 (Domain) — Port di immagine ridimensionata + taglia logica + condivisione.
//
// Diagnosi (FAST-SCAN-ENGINE-PLAN §1.2, leva 2 🔴): oggi Vision e nitidezza
// decodificano l'ORIGINALE a piena risoluzione per poi usarne un francobollo — il
// feature print normalizza internamente a piccolo, la nitidezza campiona una griglia
// da 48px. Decodificare full-res è spreco puro di CPU/memoria su ~25k foto.
//
// Questo port fa chiedere ai rilevatori l'immagine ALLA TAGLIA PICCOLA che usano
// davvero (≈224px feature print, ≈64px nitidezza), zero rete. Un originale non
// residente (solo in iCloud) con rete disabilitata → `nil`: il rilevatore degrada
// onestamente (asset non analizzabile), mai un falso risultato (manifesto §6).
//
// Altitudine (00-INDEX §1bis): il Domain resta puro. Come `AssetHandle`, l'immagine
// ridimensionata è OPACA — un riferimento senza alcun tipo grafico che l'attraversa;
// il tipo concreto (che incapsula un `CGImage`) vive nel Data. Qui vivono il
// contratto, la selezione della taglia (pura, testabile su Linux) e il decoratore di
// condivisione del decode.

/// Taglia logica di decodifica, dichiarata per rilevatore. Nessun caso "piena
/// risoluzione": la scelta stessa del tipo rende impossibile richiedere il full-res
/// per l'analisi (la vecchia via è rimossa per costruzione, FSE-C1 leva 2).
public enum LogicalImageSize: Equatable, Sendable, Hashable {
    /// Feature print semantico (Vision normalizza a piccolo): lato lungo ≈224px.
    case featurePrint
    /// Nitidezza (varianza del Laplaciano su griglia piccola): lato lungo ≈64px.
    case sharpness
    /// Taglia esplicita in pixel (lato lungo), per usi generici o di test. Confinata
    /// a ≥1 (mai zero/negativa → mai una richiesta degenere).
    case pixels(Int)

    /// Lato lungo in pixel della taglia richiesta. Piccolo di proposito: è il cuore
    /// della leva 2 (mai la piena risoluzione).
    public var longestSide: Int {
        switch self {
        case .featurePrint: return 224
        case .sharpness: return 64
        case .pixels(let side): return max(1, side)
        }
    }
}

/// Immagine ridimensionata opaca (`AnyObject`, come `AssetHandle`): il tipo concreto
/// (che incapsula un `CGImage`) vive nel Data — nessun tipo grafico attraversa il
/// confine di altitudine. Il Domain non legge mai i pixel; li instrada e basta.
public protocol DownscaledImage: AnyObject {}

/// Provider di pixel ridimensionati on-device: dato un handle (FSE-B1) e una taglia
/// logica, restituisce un'immagine piccola o `nil`.
///
/// Invariante di onestà (§6): l'implementazione reale legge con
/// `isNetworkAccessAllowed = false`; un originale non residente → `nil`, MAI un
/// download iCloud, MAI un'immagine fabbricata.
public protocol DownscaledImageProviding {
    /// Immagine ridimensionata dell'asset alla taglia richiesta, o `nil` se non
    /// producibile on-device (originale solo in iCloud, decodifica fallita).
    func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage?
}

/// Seam puro dove un rilevatore chiede l'immagine alla sua taglia. Tenendo qui la
/// SELEZIONE della taglia (pura), un oracolo CI prova che la nitidezza chiede la
/// taglia piccola dichiarata (AC-FSE-C1-1) e che un non-residente resta `nil`
/// (AC-FSE-C1-2), senza device.
public enum DownscaledImageRequest {
    public static func image(
        for handle: AssetHandle,
        size: LogicalImageSize,
        using provider: DownscaledImageProviding
    ) -> DownscaledImage? {
        provider.downscaledImage(for: handle, size: size)
    }
}

/// Decoratore che CONDIVIDE il decode: memoizza per `(id, taglia)` così due
/// rilevatori che chiedono la stessa immagine alla stessa taglia nella stessa
/// scansione paghino UN solo decode (AC-FSE-C1-3). Taglie diverse restano decode
/// distinti (onestà: nessuna condivisione fabbricata).
///
/// Onestà preservata: anche un `nil` (non residente) è memoizzato come "miss", così
/// non si ritenta a ogni confronto — e resta `nil`, mai promosso a immagine.
///
/// Memoria (leva 2): tenere ogni immagine decodificata viva farebbe esplodere la RAM
/// su 25k asset. Questo decoratore è pensato per un uso PER-ASSET nel motore
/// concorrente (FSE-D): `evictAll()` fra un asset e il successivo mantiene viva solo
/// la finestra in lavorazione. **Non è thread-safe**: la protezione sotto esecuzione
/// concorrente è di FSE-D2 (lock/attore), da validare con Thread Sanitizer (§7).
public final class SharedDownscaledImageProvider: DownscaledImageProviding {
    private struct Key: Hashable {
        let id: String
        let size: LogicalImageSize
    }
    private enum CacheEntry {
        case image(DownscaledImage)
        case miss
    }

    private let base: DownscaledImageProviding
    private var cache: [Key: CacheEntry] = [:]

    public init(base: DownscaledImageProviding) {
        self.base = base
    }

    public func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        let key = Key(id: handle.assetLocalIdentifier, size: size)
        if let entry = cache[key] {
            switch entry {
            case .image(let image): return image
            case .miss: return nil
            }
        }
        let produced = base.downscaledImage(for: handle, size: size)
        cache[key] = produced.map(CacheEntry.image) ?? .miss
        return produced
    }

    /// Rilascia le immagini memoizzate (dieta memoria). Il motore concorrente (FSE-D)
    /// la svuota per-asset così la cache non tiene viva l'intera libreria decodificata.
    public func evictAll() {
        cache.removeAll(keepingCapacity: true)
    }
}

/// Null-object: nessuna immagine producibile (grafi parziali/di test, o build senza i
/// framework grafici). Coerente con `EmptyAssetHandleResolver`/`NoSharpnessScorer`:
/// mai un'immagine finta → il rilevatore degrada a "non analizzabile".
public struct EmptyDownscaledImageProvider: DownscaledImageProviding {
    public init() {}
    public func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        nil
    }
}
