import AngavuDomain

// T-112 (wiring) — Port per lo stato di storage rilevante al CAVEAT iCLOUD della
// dashboard.
//
// Manifesto "numeri veri": mai promettere spazio-device che non si libera. Quando
// iCloud "Ottimizza spazio dispositivo" è attivo, alcuni originali vivono nel
// cloud e i byte residenti sul device ORA sono inferiori ai byte libreria — il
// caveat va SEMPRE segnalato, mai nascosto. Questa è la seam onesta che alimenta
// `ReclaimableSpaceCalculator` (T-021) con dati reali; i test la sostituiscono con
// un fake puro. Definita nel Data (concerne la piattaforma); il Domain resta puro.
public protocol DeviceStorageInspecting {
    /// Stato corrente di iCloud "ottimizza spazio dispositivo".
    func optimizeStorageStatus() -> ICloudOptimizeStorage
    /// Byte residenti sul device ORA per l'asset. Contratto d'onestà: `<= libraryBytes`
    /// (il device non può liberare più di quanto occupa in libreria).
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64
    /// P0-2: vero quando `deviceResidentBytes` è una misura REALE della residenza sul
    /// device; falso quando è solo un best-effort non affidabile (es. iCloud
    /// "ottimizza spazio" attivo senza un probe per-asset reale). Falso ⇒ la
    /// presentazione mostra un caveat "non determinabile", mai un numero fabbricato.
    func residencyIsDeterminate() -> Bool
}

public extension DeviceStorageInspecting {
    /// Default: si assume la residenza determinata. Le sorgenti che NON possono
    /// misurare la residenza (adapter reale con optimize-storage attivo) fanno
    /// l'override a `false`. Mantiene invariati i fake dei test (residenza nota).
    func residencyIsDeterminate() -> Bool { true }
}

#if canImport(Photos)
import Photos

/// Adapter reale. PhotoKit **non** espone l'impostazione "Ottimizza spazio
/// dispositivo" tramite un'API pubblica tipizzata, né la residenza per-asset in
/// modo sincrono (richiederebbe `PHAssetResourceManager` async).
///
/// Baseline **onesta e conservativa**: si assume che l'ottimizzazione POSSA
/// essere attiva (`.enabled`), così il caveat può emergere dai byte residenti
/// reali invece di essere nascosto per costruzione. La residenza per-asset è, in
/// questa versione, un best-effort che considera l'originale residente (byte
/// libreria): il rilevamento preciso della residenza in cloud (async PhotoKit) è
/// raffinato in **T-114** (report onesto). Copertura dichiarata (L-COL-006):
/// compilato in CI, comportamento a runtime sul device NON coperto da unit test.
public struct SystemDeviceStorageInspector: DeviceStorageInspecting {
    public init() {}

    public func optimizeStorageStatus() -> ICloudOptimizeStorage { .enabled }

    public func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        libraryBytes
    }

    /// P0-2 — Onestà sulla residenza. PhotoKit non espone una residenza per-asset
    /// affidabile e leggera via API pubblica (un probe reale caricherebbe dati per
    /// ogni asset: proibitivo su decine di migliaia, riporterebbe il freeze appena
    /// risolto). Quindi:
    ///   • optimize-storage DISATTIVO → ogni originale è residente: la residenza è
    ///     nota e coincide coi byte libreria → `true`;
    ///   • optimize-storage ATTIVO → alcuni originali sono nel cloud e non possiamo
    ///     misurarlo a buon mercato → residenza NON determinabile → `false`, così la
    ///     UI mostra un caveat onesto invece di un numero device gonfiato.
    /// Copertura dichiarata (L-COL-006): runtime sul device NON coperto da unit test.
    public func residencyIsDeterminate() -> Bool {
        optimizeStorageStatus() == .disabled
    }
}
#endif
