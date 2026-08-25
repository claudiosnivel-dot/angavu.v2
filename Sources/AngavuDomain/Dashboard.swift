import Foundation

// Macrotask `dashboard` — modello di dominio PURO dei numeri veri.
//
// Tre pezzi, uno per task atomico, tutti senza alcun tipo di piattaforma
// (altitudine `domain ↛ data`, 00-INDEX §1bis):
//   • T-020 aggregazione byte per categoria, exact separato da estimated;
//   • T-021 caveat iCloud: spazio libreria vs spazio device liberabile ORA;
//   • T-022 banner accesso limited: totale marcato parziale, mai spacciato per totale.
//
// Fuori scope (per blueprint): rendering SwiftUI, testo del report, styling —
// tutto in `ui_shell`. Qui vivono solo i numeri e le loro invarianti di onestà.

// MARK: - T-020 — Aggregazione numeri veri per categoria

/// Categoria di dashboard, derivata dai campi che l'indice conosce davvero
/// (`MediaKind` + sottotipo screenshot). Le categorie sono **disgiunte**: uno
/// screenshot conta solo come `screenshot`, mai anche come `photo`, così le somme
/// non si sovrappongono.
public enum DashboardCategory: String, Sendable, Equatable, CaseIterable, Codable {
    case photo
    case video
    case screenshot

    /// Categoria di un asset. Deterministica e totale.
    public static func of(_ asset: LibraryAsset) -> DashboardCategory {
        if asset.kind == .video { return .video }
        if asset.subtypes.contains(.screenshot) { return .screenshot }
        return .photo
    }
}

/// Un asset accoppiato alla sua dimensione. È l'input dell'aggregatore: tiene
/// insieme la categoria (dal `LibraryAsset`) e i byte con la loro esattezza
/// (`ByteSize`), senza che il Domain debba conoscere l'indice SwiftData.
public struct SizedAsset: Equatable, Sendable {
    public let asset: LibraryAsset
    public let size: ByteSize

    public init(asset: LibraryAsset, size: ByteSize) {
        self.asset = asset
        self.size = size
    }
}

/// Byte aggregati di una categoria, con la quota **exact** tenuta separata dalla
/// quota **estimated**: le due non vanno mai fuse in un unico numero spacciato
/// per esatto (manifesto onestà, AC-020-2).
public struct CategoryBytes: Equatable, Sendable {
    public let category: DashboardCategory
    /// Numero di asset in questa categoria.
    public let count: Int
    /// Somma dei soli byte `exact`.
    public let exactBytes: Int64
    /// Somma dei soli byte `estimated`. Questa quota resta marcata: non è esatta.
    public let estimatedBytes: Int64

    public init(category: DashboardCategory, count: Int, exactBytes: Int64, estimatedBytes: Int64) {
        self.category = category
        self.count = count
        self.exactBytes = max(0, exactBytes)
        self.estimatedBytes = max(0, estimatedBytes)
    }

    /// Byte totali della categoria (exact + estimated). Numero di comodo per
    /// l'ordinamento/visualizzazione: **non** va presentato come "esatto" quando
    /// `estimatedBytes > 0`. Chi mostra il valore usa `hasEstimatedPortion`.
    public var totalBytes: Int64 { exactBytes + estimatedBytes }

    /// Vero se parte del totale è stimata: il totale non è interamente esatto.
    public var hasEstimatedPortion: Bool { estimatedBytes > 0 }
}

/// Aggregato dell'intera dashboard: una voce per categoria presente.
public struct DashboardAggregate: Equatable, Sendable {
    /// Voci per categoria, in ordine stabile di `DashboardCategory.allCases`.
    /// Contiene solo le categorie con almeno un asset.
    public let categories: [CategoryBytes]

    public init(categories: [CategoryBytes]) {
        self.categories = categories
    }

    /// Byte di una specifica categoria, o `nil` se assente.
    public func bytes(for category: DashboardCategory) -> CategoryBytes? {
        categories.first { $0.category == category }
    }
}

/// Aggregazione pura dei byte per categoria.
public enum DashboardAggregator {
    /// Somma i byte per categoria, tenendo distinta la quota exact da quella
    /// estimated. Le categorie vuote sono omesse; l'ordine è quello stabile di
    /// `DashboardCategory.allCases`.
    public static func aggregate(_ items: [SizedAsset]) -> DashboardAggregate {
        var counts: [DashboardCategory: Int] = [:]
        var exact: [DashboardCategory: Int64] = [:]
        var estimated: [DashboardCategory: Int64] = [:]

        for item in items {
            let category = DashboardCategory.of(item.asset)
            counts[category, default: 0] += 1
            switch item.size {
            case .exact(let bytes):
                exact[category, default: 0] += bytes
            case .estimated(let bytes):
                estimated[category, default: 0] += bytes
            }
        }

        let categories = DashboardCategory.allCases.compactMap { category -> CategoryBytes? in
            guard let count = counts[category] else { return nil }
            return CategoryBytes(
                category: category,
                count: count,
                exactBytes: exact[category] ?? 0,
                estimatedBytes: estimated[category] ?? 0
            )
        }

        return DashboardAggregate(categories: categories)
    }
}

// MARK: - T-021 — Caveat iCloud: spazio libreria vs spazio device liberabile ora

/// Stato di iCloud "ottimizza spazio dispositivo". Determina se gli originali
/// possono vivere nel cloud (e quindi non liberarsi subito eliminando).
public enum ICloudOptimizeStorage: String, Sendable, Equatable, Codable {
    /// "Ottimizza spazio" attivo: alcuni originali possono essere nel cloud.
    case enabled
    /// Disattivo: ogni originale è residente sul device.
    case disabled
}

/// Capacità e spazio libero del volume del device, in byte. Tipo di dominio PURO
/// (nessun `URL`/piattaforma): il tetto di realtà (P0-3) lo consuma per non
/// stampare mai un "liberabile sul telefono" più grande di quanto il telefono
/// possa fisicamente contenere o liberare. L'adapter reale (`DeviceCapacityReading`,
/// Data) lo riempie via API pubbliche.
public struct DeviceStorageCapacity: Equatable, Sendable {
    /// Capacità totale del volume (byte).
    public let totalCapacityBytes: Int64
    /// Spazio libero utile ORA (byte), es. `volumeAvailableCapacityForImportantUsage`.
    public let availableBytes: Int64

    public init(totalCapacityBytes: Int64, availableBytes: Int64) {
        self.totalCapacityBytes = max(0, totalCapacityBytes)
        self.availableBytes = max(0, availableBytes)
    }
}

/// Spazio recuperabile, con la distinzione onesta fra libreria e device ORA.
/// Quando `reclaimableDeviceSpaceNow < reclaimableLibrarySpace` va segnalato il
/// caveat iCloud: eliminare libererà iCloud, non subito lo spazio locale.
///
/// P0-3: quando la residenza per-asset non è determinabile (`deviceSpaceIsDeterminate
/// == false`), `reclaimableDeviceSpaceNow` NON è un numero affidabile — la
/// presentazione mostra un caveat, mai la cifra. Il manifesto vieta di fabbricare
/// un numero device: meglio "non determinabile" che un valore inventato.
public struct ReclaimableSpace: Equatable, Sendable {
    /// Byte liberabili nella libreria (sorgente piena).
    public let reclaimableLibrarySpace: Int64
    /// Byte realmente liberabili sul device ORA. Affidabile solo se
    /// `deviceSpaceIsDeterminate`; altrimenti va trattato come non disponibile.
    public let reclaimableDeviceSpaceNow: Int64
    /// Vero quando la residenza sul device è stata determinata: allora
    /// `reclaimableDeviceSpaceNow` è un numero onesto. Falso ⇒ caveat, nessun numero.
    public let deviceSpaceIsDeterminate: Bool

    public init(
        reclaimableLibrarySpace: Int64,
        reclaimableDeviceSpaceNow: Int64,
        deviceSpaceIsDeterminate: Bool = true
    ) {
        let library = max(0, reclaimableLibrarySpace)
        self.reclaimableLibrarySpace = library
        // Invariante di onestà: il device non può liberare più della libreria.
        self.reclaimableDeviceSpaceNow = min(library, max(0, reclaimableDeviceSpaceNow))
        self.deviceSpaceIsDeterminate = deviceSpaceIsDeterminate
    }

    /// Vero quando la residenza sul device NON è determinabile: la cifra device va
    /// sostituita da un caveat, mai mostrata come numero (manifesto: no numeri finti).
    public var deviceSpaceIsIndeterminate: Bool { !deviceSpaceIsDeterminate }

    /// Vero quando parte dello spazio libreria non si libera sul device ora
    /// (originali in iCloud) OPPURE la residenza è indeterminata: mai da nascondere.
    /// In entrambi i casi "elimini la libreria, non subito lo spazio sul telefono".
    public var iCloudCaveat: Bool {
        deviceSpaceIsIndeterminate || reclaimableDeviceSpaceNow < reclaimableLibrarySpace
    }
}

/// Calcolo puro dello spazio recuperabile a partire dai byte per-asset.
///
/// Riusa il concetto di `DeletedAssetSize` (byte libreria vs byte residenti sul
/// device) già introdotto da T-052: la dashboard aggrega gli stessi valori, non
/// ne conia di nuovi.
public enum ReclaimableSpaceCalculator {
    /// Somma i byte libreria; i byte device liberabili ORA dipendono dallo stato
    /// iCloud optimize-storage:
    ///  • `disabled` → nessuna quota bloccata in cloud: device == libreria (AC-021-2);
    ///  • `enabled`  → device = somma dei byte residenti, che può essere inferiore
    ///    quando alcuni originali sono nel cloud → caveat (AC-021-1).
    ///
    /// **P0-3 — tetto di realtà.** Il "liberabile sul telefono ora" non può superare
    /// né la libreria, né lo spazio libero del device, né la sua capacità: quando
    /// `deviceCapacity` è noto, il device-now è limitato a
    /// `min(residente, liberoDevice, capacità)`. È un tetto **conservativo** — guarda
    /// contro la sovrastima (il bug "139 GB su un telefono da 128"): con la residenza
    /// per-asset corretta il tetto raramente vincola; se una grande quota fosse
    /// residente su un device quasi pieno può sotto-stimare, ma il manifesto preferisce
    /// sotto-stimare che gonfiare.
    ///
    /// **P0-3 — residenza indeterminata.** Se il chiamante non ha potuto determinare la
    /// residenza (`residencyDeterminate == false`), lo spazio device non è un numero
    /// affidabile: si restituisce uno `ReclaimableSpace` marcato indeterminato (la
    /// presentazione mostra un caveat, non una cifra fabbricata).
    public static func reclaimable(
        from items: [DeletedAssetSize],
        optimizeStorage: ICloudOptimizeStorage,
        deviceCapacity: DeviceStorageCapacity? = nil,
        residencyDeterminate: Bool = true
    ) -> ReclaimableSpace {
        let library = items.reduce(Int64(0)) { $0 + $1.libraryBytes }

        // Residenza non determinabile: nessun numero device, solo caveat.
        guard residencyDeterminate else {
            return ReclaimableSpace(
                reclaimableLibrarySpace: library,
                reclaimableDeviceSpaceNow: 0,
                deviceSpaceIsDeterminate: false
            )
        }

        let deviceRaw: Int64
        switch optimizeStorage {
        case .disabled:
            // Nessuna quota in cloud: ogni originale è residente → device == libreria.
            deviceRaw = library
        case .enabled:
            // Somma dei byte residenti; può essere inferiore (originali nel cloud).
            deviceRaw = items.reduce(Int64(0)) { $0 + $1.deviceResidentBytes }
        }

        // Tetto di realtà: mai oltre lo spazio libero né la capacità del device.
        let deviceCapped = capToReality(deviceRaw, within: deviceCapacity)

        return ReclaimableSpace(
            reclaimableLibrarySpace: library,
            reclaimableDeviceSpaceNow: deviceCapped
        )
    }

    /// Applica il tetto di realtà `min(value, liberoDevice, capacità)` quando la
    /// capacità è nota; altrimenti lascia il valore invariato (nessun tetto ⇒
    /// comportamento storico). Il cap `<= libreria` resta a carico di `ReclaimableSpace`.
    private static func capToReality(_ value: Int64, within capacity: DeviceStorageCapacity?) -> Int64 {
        guard let capacity else { return value }
        return min(value, min(capacity.availableBytes, capacity.totalCapacityBytes))
    }
}

// MARK: - T-022 — Banner accesso limited

/// Stato del banner di accesso della dashboard, derivato da `PhotoAccess`.
/// Con accesso `limited` il totale è per forza parziale e va dichiarato tale.
public struct DashboardBanner: Equatable, Sendable {
    /// Vero quando l'accesso è `limited`: mostrare l'invito ad abilitare l'accesso
    /// completo.
    public let showLimitedAccessBanner: Bool
    /// Vero quando il totale mostrato è parziale (non copre l'intera libreria).
    public let isTotalPartial: Bool

    public init(showLimitedAccessBanner: Bool, isTotalPartial: Bool) {
        self.showLimitedAccessBanner = showLimitedAccessBanner
        self.isTotalPartial = isTotalPartial
    }
}

/// Policy pura del banner: traduce l'accesso nello stato del banner, riusando
/// `PhotoAccessPolicy` (unica fonte del "conteggio parziale").
public enum DashboardBannerPolicy {
    /// Deriva lo stato del banner dalla modalità d'accesso. Il totale è marcato
    /// parziale se e solo se `PhotoAccessPolicy` lo considera parziale (limited).
    public static func banner(for access: PhotoAccess) -> DashboardBanner {
        let decision = PhotoAccessPolicy.decide(for: access)
        return DashboardBanner(
            showLimitedAccessBanner: access == .limited,
            isTotalPartial: decision.isPartialCount
        )
    }

    /// Comodità: deriva direttamente dal provider d'accesso.
    public static func banner(from provider: PhotoAccessProviding) -> DashboardBanner {
        banner(for: provider.currentAccess())
    }
}
