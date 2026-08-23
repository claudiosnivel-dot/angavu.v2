import AngavuDomain
import Observation

// T-114 (wiring) — Report onesto sui dati veri.
//
// Alimenta lo `HonestReport` (T-102) con i numeri veri della libreria letti dal
// lettore condiviso (LibraryFiguresReader): spazio recuperabile in libreria vs
// device ORA e caveat iCloud, senza coniare tipi nuovi né promettere spazio
// device oltre il recuperabile reale. Nessuna logica di dominio nuova: cablaggio.

/// Modello di presentazione del report onesto: il report di dominio più gli
/// accessi comodi ai numeri che la View mostra.
public struct HonestReportScreen: Equatable, Sendable {
    public let report: HonestReport

    public init(report: HonestReport) {
        self.report = report
    }

    /// Byte liberabili nella libreria (sorgente piena).
    public var libraryReclaimable: Int64 { report.reclaimable.reclaimableLibrarySpace }
    /// Byte realmente liberabili sul device ORA (mai promessi oltre il reale).
    public var deviceReclaimableNow: Int64 { report.reclaimable.reclaimableDeviceSpaceNow }
    /// Vero quando parte dello spazio libreria non si libera sul device ora
    /// (originali in iCloud): sempre dichiarato, mai nascosto.
    public var iCloudCaveat: Bool { report.iCloudCaveat }
}

/// Stato esplicito del report. Nessun blocco muto: ogni esito è uno di questi.
public enum HonestReportState: Equatable, Sendable {
    case idle
    case ready(HonestReportScreen)
    case failed(String)
}

@Observable
public final class HonestReportViewModel {
    public private(set) var state: HonestReportState = .idle

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Compone il report onesto dai dati veri e restituisce lo stato finale. La
    /// lettura dell'indice può fallire: in tal caso lo stato è `failed`, mai un
    /// verde finto.
    @discardableResult
    public func load() -> HonestReportState {
        do {
            let figures = try LibraryFiguresReader.read(from: environment)
            let report = HonestReportComposer.compose(
                aggregate: figures.aggregate,
                reclaimable: figures.reclaimable,
                access: figures.access
            )
            state = .ready(HonestReportScreen(report: report))
        } catch {
            state = .failed(String(describing: error))
        }
        return state
    }
}
