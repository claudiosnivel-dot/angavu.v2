import AngavuDomain
import Observation

// T-112 (wiring) — Dashboard reale come view-model osservabile.
//
// Non introduce logica nuova: cabla i dati veri dell'indice negli aggregatori già
// verdi del macrotask `dashboard`:
//   • DashboardAggregator       (T-020) — byte per categoria, exact separato da estimated;
//   • ReclaimableSpaceCalculator(T-021) — spazio libreria vs device ORA + caveat iCloud;
//   • DashboardBannerPolicy     (T-022) — banner accesso limited + totale marcato parziale.
// Tutto dietro i port dell'AppEnvironment, quindi testabile con fake senza device.
// Altitudine invariata: Features consuma i port; il Domain resta puro.

/// Modello di presentazione della dashboard: solo dati onesti, pronti per la View.
public struct DashboardScreen: Equatable, Sendable {
    /// Righe per categoria coi byte veri (exact/estimated separati, mai fusi).
    public let categories: [CategoryBytes]
    /// Spazio recuperabile con la distinzione libreria vs device ora (caveat iCloud).
    public let reclaimable: ReclaimableSpace
    /// Stato del banner: accesso limited + se il totale mostrato è parziale.
    public let banner: DashboardBanner

    public init(categories: [CategoryBytes], reclaimable: ReclaimableSpace, banner: DashboardBanner) {
        self.categories = categories
        self.reclaimable = reclaimable
        self.banner = banner
    }

    /// Vero quando i totali NON coprono l'intera libreria (accesso limited): il
    /// numero mostrato è parziale e va dichiarato tale, mai spacciato per totale.
    public var isTotalPartial: Bool { banner.isTotalPartial }
}

/// Stato esplicito della dashboard. Nessun blocco muto: ogni esito è uno di questi.
public enum DashboardState: Equatable, Sendable {
    case idle
    case ready(DashboardScreen)
    case failed(String)
}

@Observable
public final class DashboardViewModel {
    public private(set) var state: DashboardState = .idle

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Costruisce la dashboard dai dati veri dell'indice (lettore condiviso
    /// `LibraryFiguresReader`) e restituisce lo stato finale. La lettura
    /// dell'indice può fallire: in tal caso lo stato è `failed`, mai un verde finto.
    ///
    /// `async` e NON isolata al main: la View la invoca con `.task`, così la lettura
    /// pesante (risoluzione byte per-asset via PhotoKit su 25k elementi) gira FUORI
    /// dal main thread — altrimenti la Dashboard si bloccherebbe come faceva la
    /// scansione. Lo stato passa a `.ready`/`.failed` solo alla fine; nel frattempo
    /// resta `.idle` e la View mostra lo spinner etichettato «Calcolo dei numeri veri…».
    @discardableResult
    public func load() async -> DashboardState {
        do {
            let figures = try LibraryFiguresReader.read(from: environment)
            state = .ready(DashboardScreen(
                categories: figures.aggregate.categories,
                reclaimable: figures.reclaimable,
                banner: DashboardBannerPolicy.banner(for: figures.access)
            ))
        } catch {
            state = .failed(String(describing: error))
        }
        return state
    }

    /// P0-1: applica un risultato già calcolato (dalla cache sopra la view,
    /// `AnalysisResultsStore`) senza ricalcolare — così tornare sulla dashboard o
    /// riemergere dal background non rifà la lettura pesante dell'indice.
    public func present(_ screen: DashboardScreen) {
        state = .ready(screen)
    }
}
