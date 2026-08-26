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
    /// P0-2b: ultima misura di residenza per-asset (dal probe device, off-main). Nil o
    /// indeterminata ⇒ la dashboard mostra il caveat P0-3, mai un numero fabbricato.
    private var residency: ResidencyMeasurement?

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
            let figures = try LibraryFiguresReader.read(from: environment, measuredResidency: residency)
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

    /// P0-2b — Misura la residenza per-asset reale e ricarica la dashboard col numero
    /// device onesto (~8 GB sul device di test) invece del caveat. Il probe device è
    /// bloccante per asset ma gira a blocchi cancellabili (`ResidencyAggregator`) su
    /// questo contesto async NON isolato al main → nessun freeze della UI. Una misura
    /// cancellata o incompleta resta indeterminata: si torna al caveat, mai un numero
    /// parziale. Copertura (L-COL-006): l'aggregazione è coperta dall'oracolo di
    /// dominio; il probe PhotoKit reale è device-only (runtime non coperto in CI).
    @discardableResult
    public func measureResidency(cancellation: CancellationToken = CancellationToken()) async -> DashboardState {
        let items = (try? LibraryFiguresReader.probeItems(from: environment)) ?? []
        let outcome = ResidencyAggregator.measure(
            items: items,
            probe: environment.residencyProbe,
            cancellation: cancellation
        )
        residency = ResidencyAggregator.measurement(from: outcome)
        return await load()
    }

    /// P0-1: applica un risultato già calcolato (dalla cache sopra la view,
    /// `AnalysisResultsStore`) senza ricalcolare — così tornare sulla dashboard o
    /// riemergere dal background non rifà la lettura pesante dell'indice.
    public func present(_ screen: DashboardScreen) {
        state = .ready(screen)
    }
}
