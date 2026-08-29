import Foundation

// FSE-E3 (Domain) — Cablaggio get-or-compute della cache dei derivati (leva 5).
//
// La persistenza (FSE-E2) e la policy di validità (FSE-E1) esistono già; qui vive il
// MECCANISMO che le usa: un adapter costoso (il feature print) consulta la cache PRIMA
// di calcolare e vi scrive solo sul cache-miss, e l'invalidazione per-asset scatta su
// cambio libreria / eliminazione. Tutto puro (Foundation): il feature print è `Data`
// OPACO, mai un tipo di Vision → l'altitudine (00-INDEX §1bis) resta intatta e gli AC
// sono testabili su Linux.
//
// Copertura (L-COL-006): la LOGICA (get-or-compute / merge per-campo / invalidazione)
// è coperta dai target_tests; il PRODUTTORE reale (Vision) e il risolutore di versione
// reale (PhotoKit `modificationDate`) sono device-only, e la composizione nella
// scansione unificata (thread dei vettori attraverso le fasi) è FSE-F.

/// Port che risolve la VERSIONE DEL CONTENUTO di un asset — in produzione la
/// `modificationDate`/versione di PhotoKit — così un `DerivedKey` può dire quando il
/// contenuto è cambiato. Nessun default: senza un risolutore reale la cache non può
/// giudicare la freschezza, e una versione fabbricata servirebbe derivati stantìi.
public protocol AssetContentVersioning {
    /// Versione stabile del contenuto dell'asset: cambia quando l'asset è modificato.
    func contentVersion(for asset: LibraryAsset) -> String
}

/// Port del PRODUTTORE del vettore feature print serializzato (bytes OPACHI). È la parte
/// COSTOSA (Vision legge i pixel); la distanza fra due vettori è a parte e a buon mercato
/// (FSE-F). Il Domain non vede mai un tipo di Vision: solo `Data`.
public protocol FeaturePrintVectorProducing {
    /// Vettore serializzato dell'asset, o `nil` se non calcolabile on-device (es.
    /// originale solo in iCloud). `nil` non è mai un vettore fabbricato.
    func vector(for asset: LibraryAsset) throws -> Data?
}

/// Cache in memoria dei derivati, sostenuta dallo store persistito (FSE-E2) e dalla
/// policy di validità (FSE-E1). È l'UNICA scrittrice della riga per-id: `merge` fa
/// read-modify-write sull'intero `DerivedRecordValue`, così adapter di campi diversi
/// (feature print oggi; hash / nitidezza / residenza in FSE-F) non si sovrascrivono a
/// vicenda passando dallo stesso store. Thread-safe: gli adapter girano off-main e in
/// parallelo (FSE-D2), quindi ogni accesso allo stato è sotto un unico lock.
public final class DerivedResultCache {
    private let store: any DerivedResultStoring
    private let lock = NSLock()
    /// Chiave corrente in memoria per id (identità + versione del contenuto in cache).
    private var keys: [String: DerivedKey] = [:]
    /// Valori derivati in memoria per id (specchio dei persistiti riusabili + freschi).
    private var values: [String: DerivedRecordValue] = [:]

    public init(store: any DerivedResultStoring) {
        self.store = store
    }

    /// Carica i persistiti e tiene in memoria SOLO quelli validi per gli asset correnti
    /// (partizione FSE-E1); scarta dallo store i derivati di asset non più presenti (mai
    /// numeri di fantasmi). Da chiamare a inizio scansione, prima dei get-or-compute.
    public func warm(current: [DerivedKey]) throws {
        let persisted = try store.loadAll()
        let partition = DerivedResultValidity.partition(
            current: current,
            persisted: Array(persisted.keys)
        )
        lock.lock()
        keys.removeAll(keepingCapacity: true)
        values.removeAll(keepingCapacity: true)
        for key in partition.reusable {
            keys[key.id] = key
            values[key.id] = persisted[key]
        }
        lock.unlock()

        let removedIDs = partition.removed.map(\.id)
        if !removedIDs.isEmpty {
            try store.remove(ids: removedIDs)
        }
    }

    /// Il valore in cache per la chiave, SSE la chiave in memoria per quell'id combacia
    /// (stesso contenuto). Chiave diversa → `nil`: mai un derivato stantìo servito.
    public func validValue(for key: DerivedKey) -> DerivedRecordValue? {
        lock.lock()
        defer { lock.unlock() }
        guard keys[key.id] == key else { return nil }
        return values[key.id]
    }

    /// Read-modify-write della riga per-id verso lo store. Se la chiave in memoria per
    /// l'id differisce (contenuto cambiato) riparte da un valore VUOTO: gli altri campi
    /// stantìi vengono scartati, non riscritti come freschi.
    public func merge(key: DerivedKey, _ mutate: (inout DerivedRecordValue) -> Void) throws {
        lock.lock()
        var value = (keys[key.id] == key ? values[key.id] : nil) ?? DerivedRecordValue()
        mutate(&value)
        keys[key.id] = key
        values[key.id] = value
        lock.unlock()

        try store.upsert([key: value])
    }

    /// Invalidazione PER-ASSET (cambio libreria / eliminazione confermata): il prossimo
    /// uso di quegli id ricalcola, mai un vettore stantìo.
    public func invalidate(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        lock.lock()
        for id in ids {
            keys.removeValue(forKey: id)
            values.removeValue(forKey: id)
        }
        lock.unlock()

        try store.remove(ids: ids)
    }

    /// Invalidazione totale (cambio libreria completo).
    public func invalidateAll() throws {
        lock.lock()
        keys.removeAll()
        values.removeAll()
        lock.unlock()

        try store.removeAll()
    }
}

/// Decoratore get-or-compute del produttore di vettori: consulta la cache derivata PRIMA
/// di calcolare, calcola solo sul miss e ci scrive (AC-FSE-E3-1). Il produttore di base
/// (Vision) NON viene chiamato quando il vettore è già in cache e valido.
public final class CachingFeaturePrintVectors: FeaturePrintVectorProducing {
    private let base: any FeaturePrintVectorProducing
    private let cache: DerivedResultCache
    private let versioning: any AssetContentVersioning

    public init(
        base: any FeaturePrintVectorProducing,
        cache: DerivedResultCache,
        versioning: any AssetContentVersioning
    ) {
        self.base = base
        self.cache = cache
        self.versioning = versioning
    }

    public func vector(for asset: LibraryAsset) throws -> Data? {
        let key = DerivedKey(
            id: asset.id,
            contentVersion: versioning.contentVersion(for: asset)
        )
        if let cached = cache.validValue(for: key)?.featurePrint {
            return cached // HIT: il produttore di base non viene mai chiamato.
        }
        let computed = try base.vector(for: asset)
        if let computed {
            try cache.merge(key: key) { $0.featurePrint = computed }
        }
        return computed
    }
}

// MARK: - FSE-J6 (censimento C3) — cablaggio del digest nella scansione reale

/// Versioning PURO del contenuto, derivato dai soli campi già indicizzati dell'asset
/// (`creationDate` + dimensioni in pixel): NESSUN fetch PhotoKit. Tiene la chiave della
/// cache stabile fra scansioni non modificate (stessa chiave → HIT) SENZA il costo di una
/// risoluzione per-asset a inizio scansione, così il `warm` su ~25k asset resta O(N) puro.
///
/// Onestà (L-COL-006): NON è il segnale forte. Un montaggio che cambia i pixel senza
/// mutare le dimensioni (es. un filtro) non muove questa versione — a coprirlo è
/// l'observer dei cambi libreria (FSE-J5), che al `photoLibraryDidChange` pota il derivato
/// dell'id toccato mentre l'app è viva. Un adapter basato su `PHAsset.modificationDate`
/// sarebbe il segnale più stretto, ma è device-only e a costo di risoluzione per-asset
/// (§7): qui si sceglie il segnale puro + l'invalidazione dell'observer, mai un ricalcolo
/// per-asset dentro il `warm`. Il residuo (un montaggio a dimensioni invariate mentre
/// l'app è chiusa) è un limite dichiarato device-only, non un falso "via libera": i
/// duplicati esatti richiedono comunque byte identici per raggrupparsi.
public struct AssetFieldContentVersioning: AssetContentVersioning {
    public init() {}

    public func contentVersion(for asset: LibraryAsset) -> String {
        let created = asset.creationDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "nil"
        return "\(created)|\(asset.pixelSize.width)x\(asset.pixelSize.height)"
    }
}

/// Decoratore get-or-compute del DIGEST di contenuto (in produzione SHA-256): consulta la
/// cache derivata PRIMA di leggere i byte on-device e calcolare, calcola solo sul miss e
/// scrive il risultato nel campo `.digest` dello stesso record per-id. Il produttore di
/// base (che legge i byte reali) NON viene chiamato quando il digest è già in cache e
/// valido → una SECONDA scansione riusa i digest persistiti (0 ricalcoli, AC-FSE-J6-1),
/// coerente con FSE-E3. `merge` fa read-modify-write dell'intero `DerivedRecordValue`,
/// quindi non sovrascrive gli altri campi (nitidezza, feature print, residenza) dello
/// stesso id. Contratto invariato di `AssetContentHashing`: `nil` resta `nil` (un asset
/// non leggibile on-device non viene mai dichiarato duplicato) e non viene persistito.
public final class CachingContentDigests: AssetContentHashing {
    private let base: any AssetContentHashing
    private let cache: DerivedResultCache
    private let versioning: any AssetContentVersioning

    public init(
        base: any AssetContentHashing,
        cache: DerivedResultCache,
        versioning: any AssetContentVersioning
    ) {
        self.base = base
        self.cache = cache
        self.versioning = versioning
    }

    public func digest(for asset: LibraryAsset) throws -> AssetDigest? {
        let key = DerivedKey(
            id: asset.id,
            contentVersion: versioning.contentVersion(for: asset)
        )
        if let cached = cache.validValue(for: key)?.digest {
            return AssetDigest(cached) // HIT: i byte non vengono mai riletti né ri-hashati.
        }
        let computed = try base.digest(for: asset)
        if let computed {
            try cache.merge(key: key) { $0.digest = computed.value }
        }
        return computed
    }
}
