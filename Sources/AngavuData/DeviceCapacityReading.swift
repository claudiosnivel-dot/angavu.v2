import Foundation
import AngavuDomain

// P0-2 — Port per capacità e spazio libero del volume del device.
//
// Alimenta il "tetto di realtà" del calcolo dello spazio recuperabile (P0-3): il
// "liberabile sul telefono ora" non può mai superare lo spazio libero né la
// capacità del device (il bug "139 GB su un telefono da 128"). Definito nel Data
// (concerne il filesystem/piattaforma); il Domain resta puro e riceve solo il
// tipo puro `DeviceStorageCapacity`. I test iniettano un fake.
public protocol DeviceCapacityReading {
    /// Capacità e spazio libero del device ORA, o `nil` se non determinabili.
    /// `nil` ⇒ nessun tetto applicato (comportamento storico), mai un numero finto.
    func deviceCapacity() -> DeviceStorageCapacity?
}

/// Null-object: capacità sconosciuta. È il default dell'`AppEnvironment` finché il
/// grafo reale non inietta l'adapter di sistema, così i test e i costruttori
/// esistenti restano invariati (nessun tetto = comportamento storico).
public struct UnknownDeviceCapacity: DeviceCapacityReading {
    public init() {}
    public func deviceCapacity() -> DeviceStorageCapacity? { nil }
}

/// Adapter reale via **API pubbliche** Foundation (nessuna API privata, App
/// Store-safe): `volumeAvailableCapacityForImportantUsage` (spazio liberabile utile
/// ORA) e `volumeTotalCapacity` (capacità del volume). Copertura dichiarata
/// (L-COL-006): compilato in CI, valori a runtime sul device NON coperti da unit test.
public struct SystemDeviceCapacityReader: DeviceCapacityReading {
    public init() {}

    public func deviceCapacity() -> DeviceStorageCapacity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) else { return nil }

        // `volumeAvailableCapacityForImportantUsage` è Int64?; `volumeTotalCapacity` è Int?.
        guard let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }

        return DeviceStorageCapacity(
            totalCapacityBytes: Int64(total),
            availableBytes: available
        )
    }
}
