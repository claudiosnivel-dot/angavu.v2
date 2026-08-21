import Foundation

// T-052 — Riepilogo post-eliminazione onesto.
//
// Manifesto "numeri veri": mai promettere spazio-device che non si libera. Il
// riepilogo distingue lo spazio LIBRERIA liberato (byte sorgente pieni) dallo
// spazio DEVICE realmente liberabile ORA. Con iCloud "ottimizza spazio" attivo,
// parte dei byte vive nel cloud e non è residente sul device: `deviceBytesReclaimableNow`
// risulta inferiore e il caveat iCloud viene segnalato.
//
// NB: il concetto di caveat iCloud è di pertinenza del macrotask `dashboard`
// (T-021). Qui è modellato al minimo indispensabile — per-asset i byte residenti
// sul device — così che la rete di sicurezza chiuda un riepilogo onesto; T-021
// consumerà/condividerà lo stesso concetto per l'aggregazione della dashboard.

/// Byte di un asset eliminato, distinti fra libreria e residenza sul device.
public struct DeletedAssetSize: Equatable, Sendable {
    /// Byte occupati nella libreria (sorgente piena).
    public let libraryBytes: Int64
    /// Byte realmente residenti sul device ORA. Con iCloud optimize-storage può
    /// essere inferiore a `libraryBytes` (originale nel cloud). Sempre `<= libraryBytes`.
    public let deviceResidentBytes: Int64

    public init(libraryBytes: Int64, deviceResidentBytes: Int64) {
        let library = max(0, libraryBytes)
        self.libraryBytes = library
        // Invariante di onestà: i byte device non possono superare quelli libreria.
        self.deviceResidentBytes = min(library, max(0, deviceResidentBytes))
    }
}

/// Riepilogo onesto di un'eliminazione. `deviceBytesReclaimableNow <= libraryBytesFreed`
/// sempre; quando è strettamente minore, `iCloudCaveat` è vero.
public struct DeletionSummary: Equatable, Sendable {
    /// Quanti asset sono stati eliminati.
    public let count: Int
    /// Byte liberati nella libreria (somma dei byte sorgente).
    public let libraryBytesFreed: Int64
    /// Byte realmente liberabili sul device ORA (somma dei byte residenti).
    public let deviceBytesReclaimableNow: Int64
    /// Vero quando parte dello spazio libreria NON si libera sul device ora
    /// (originali in iCloud): va segnalato, mai nascosto.
    public let iCloudCaveat: Bool

    public init(
        count: Int,
        libraryBytesFreed: Int64,
        deviceBytesReclaimableNow: Int64,
        iCloudCaveat: Bool
    ) {
        self.count = count
        self.libraryBytesFreed = libraryBytesFreed
        self.deviceBytesReclaimableNow = deviceBytesReclaimableNow
        self.iCloudCaveat = iCloudCaveat
    }
}

/// Composizione pura del riepilogo dagli asset eliminati.
public enum DeletionSummaryComposer {
    /// Compone il `DeletionSummary` sommando i byte. Il caveat iCloud è derivato,
    /// non dichiarato: è vero se e solo se i byte liberabili sul device sono meno
    /// di quelli liberati in libreria.
    public static func compose(_ items: [DeletedAssetSize]) -> DeletionSummary {
        let library = items.reduce(Int64(0)) { $0 + $1.libraryBytes }
        let device = items.reduce(Int64(0)) { $0 + $1.deviceResidentBytes }
        return DeletionSummary(
            count: items.count,
            libraryBytesFreed: library,
            deviceBytesReclaimableNow: device,
            iCloudCaveat: device < library
        )
    }
}
