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
