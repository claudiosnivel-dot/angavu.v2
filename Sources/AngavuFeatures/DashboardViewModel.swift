import AngavuDomain
import AngavuData
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

    private let indexReader: any AssetIndexReading
    private let byteResolver: any AssetByteSizeResolving
    private let accessProvider: any PhotoAccessProviding
    private let deviceStorage: any DeviceStorageInspecting

    public init(environment: AppEnvironment) {
        self.indexReader = environment.indexReader
        self.byteResolver = environment.byteResolver
        self.accessProvider = environment.authorizer
        self.deviceStorage = environment.deviceStorage
    }

    /// Costruisce la dashboard dai dati veri dell'indice e restituisce lo stato
    /// finale. La lettura dell'indice può fallire: in tal caso lo stato è `failed`,
    /// mai un verde finto.
    @discardableResult
    public func load() -> DashboardState {
        do {
            let assets = try indexReader.assets(matching: .all)

            // Un asset alla volta: byte reali dietro il port (exact se disponibile,
            // altrimenti stima esplicita marcata dal ByteSizePolicy del Data).
            let sized = assets.map { asset -> SizedAsset in
                SizedAsset(
                    asset: asset,
                    size: byteResolver.byteSize(
                        forLocalIdentifier: asset.id,
                        fallbackEstimate: Self.fallbackEstimate(for: asset)
                    )
                )
            }

            let aggregate = DashboardAggregator.aggregate(sized)

            // Spazio recuperabile: byte libreria da ogni asset, byte device dal
            // port di residenza; il calcolo del caveat è del Domain (T-021).
            let deletedSizes = sized.map { item -> DeletedAssetSize in
                let libraryBytes = item.size.bytes
                return DeletedAssetSize(
                    libraryBytes: libraryBytes,
                    deviceResidentBytes: deviceStorage.deviceResidentBytes(
                        forLocalIdentifier: item.asset.id,
                        libraryBytes: libraryBytes
                    )
                )
            }
            let reclaimable = ReclaimableSpaceCalculator.reclaimable(
                from: deletedSizes,
                optimizeStorage: deviceStorage.optimizeStorageStatus()
            )

            let banner = DashboardBannerPolicy.banner(from: accessProvider)

            state = .ready(DashboardScreen(
                categories: aggregate.categories,
                reclaimable: reclaimable,
                banner: banner
            ))
        } catch {
            state = .failed(String(describing: error))
        }
        return state
    }

    /// Stima di ripiego (byte) usata SOLO quando il file-size esatto non è
    /// disponibile: il `ByteSizePolicy` la marca `estimated`, mai `exact`. Rozza,
    /// derivata dall'area in pixel (≈2 byte/pixel per un asset compresso).
    private static func fallbackEstimate(for asset: LibraryAsset) -> Int64 {
        let pixels = Int64(asset.pixelSize.width) * Int64(asset.pixelSize.height)
        return max(0, pixels * 2)
    }
}
