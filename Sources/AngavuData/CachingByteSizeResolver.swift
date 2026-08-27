import Foundation
import AngavuDomain

// FSE-B2 (Data) — Byte size risolti una volta e riusati (fine della tripla risoluzione).
//
// Diagnosi (FAST-SCAN-ENGINE-PLAN §1.3, leva 6 🟡): oggi i byte per-asset sono
// risolti da PhotoKit (`PHAssetResource.fileSize`) OGNI volta che una schermata li
// chiede — la dashboard, poi «duplicati», poi «grandi/vecchi» risolvono gli stessi
// ~25k asset 3×. La risoluzione è costosa (un fetch + enumerazione risorse per asset).
//
// Questo decoratore mette una cache `id → ByteSize` DAVANTI a qualunque
// `AssetByteSizeResolving`: la prima risoluzione (tipicamente la fase `resolvingSizes`
// della scansione) scalda la cache; ogni uso successivo (le sorgenti di categoria) è un
// HIT → il resolver base non è più invocato per gli asset già noti. Un asset NUOVO (non
// pre-risolto) è risolto on-demand UNA sola volta e poi cachato.
//
// Onestà (00-INDEX §6): la cache conserva il `ByteSize` COMPLETO — `exact` resta exact,
// `estimated` resta estimated (mai una stima promossa a esatta, mai un mancante
// spacciato per 0: il valore cachato è esattamente quello prodotto dal base). La chiave
// è il solo `localIdentifier`: entro una sessione il `ByteSize` di un asset è stabile
// (il `fallbackEstimate` è derivato dai pixel dell'asset, deterministico per id).
// L'invalidazione su CAMBIO CONTENUTO tra avvii (chiave id+versione) è FSE-E, fuori
// scope: qui la cache vive in memoria per la sessione (istanza condivisa via
// `AppEnvironment`). Zero rete, nessun tipo di piattaforma: logica pura.

/// Cache in-memory `id → ByteSize` davanti a un resolver base. Riferimento (`final
/// class`) di proposito: la STESSA istanza è condivisa dall'`AppEnvironment` fra la
/// scansione (che scalda) e le sorgenti di categoria (che riusano).
public final class CachingByteSizeResolver: AssetByteSizeResolving {
    private let base: any AssetByteSizeResolving
    private var cache: [String: ByteSize] = [:]
    /// Protegge il dizionario: la scansione risolve fuori dal main, le categorie pure.
    /// Sotto esecuzione CONCORRENTE (FSE-D) un doppio calcolo dello stesso id nella
    /// finestra fra miss e store è possibile ma innocuo (stesso valore deterministico) —
    /// la correttezza del dizionario resta garantita; l'ottimizzazione fine è di FSE-D2.
    private let lock = NSLock()

    public init(base: any AssetByteSizeResolving) {
        self.base = base
    }

    public func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        lock.lock()
        let cached = cache[localIdentifier]
        lock.unlock()
        if let cached {
            return cached   // HIT: il base NON viene invocato (fine della ri-risoluzione)
        }

        let resolved = base.byteSize(forLocalIdentifier: localIdentifier, fallbackEstimate: fallbackEstimate)

        lock.lock()
        cache[localIdentifier] = resolved
        lock.unlock()
        return resolved
    }

    /// Numero di asset con byte già noti (per ispezione/diagnostica). Non usato in
    /// produzione per decisioni; utile a provare il riuso.
    public var knownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}
