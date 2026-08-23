import AngavuDomain
import AngavuData

// T-114 (wiring) — Lettura condivisa dei numeri VERI della libreria dai port
// dell'AppEnvironment. Un solo posto per: leggere l'indice, risolvere i byte
// (exact/estimated), aggregare per categoria e calcolare lo spazio recuperabile
// col caveat iCloud. Condiviso dai view-model che presentano dati aggregati —
// dashboard (T-112) e report onesto (T-114) — così non duplicano il cablaggio.

/// Numeri veri della libreria, pronti da comporre in una schermata.
struct LibraryFigures {
    let aggregate: DashboardAggregate
    let reclaimable: ReclaimableSpace
    let access: PhotoAccess
}

enum LibraryFiguresReader {
    /// Legge i numeri veri dietro i port dell'ambiente. Può lanciare: la lettura
    /// dell'indice non va mai mascherata con un verde finto.
    static func read(from environment: AppEnvironment) throws -> LibraryFigures {
        let assets = try environment.indexReader.assets(matching: .all)

        // Un asset alla volta: byte reali dietro il port (exact se disponibile,
        // altrimenti stima esplicita marcata dal ByteSizePolicy del Data).
        let sized = assets.map { asset -> SizedAsset in
            SizedAsset(
                asset: asset,
                size: environment.byteResolver.byteSize(
                    forLocalIdentifier: asset.id,
                    fallbackEstimate: fallbackEstimate(for: asset)
                )
            )
        }
        let aggregate = DashboardAggregator.aggregate(sized)

        // Spazio recuperabile: byte libreria da ogni asset, byte device dal port di
        // residenza; il calcolo del caveat iCloud è del Domain (T-021).
        let deleted = sized.map { item -> DeletedAssetSize in
            let libraryBytes = item.size.bytes
            return DeletedAssetSize(
                libraryBytes: libraryBytes,
                deviceResidentBytes: environment.deviceStorage.deviceResidentBytes(
                    forLocalIdentifier: item.asset.id,
                    libraryBytes: libraryBytes
                )
            )
        }
        let reclaimable = ReclaimableSpaceCalculator.reclaimable(
            from: deleted,
            optimizeStorage: environment.deviceStorage.optimizeStorageStatus()
        )

        return LibraryFigures(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: environment.authorizer.currentAccess()
        )
    }

    /// Stima di ripiego (byte) usata SOLO quando il file-size esatto non è
    /// disponibile: il `ByteSizePolicy` la marca `estimated`, mai `exact`. Rozza,
    /// derivata dall'area in pixel (≈2 byte/pixel per un asset compresso).
    static func fallbackEstimate(for asset: LibraryAsset) -> Int64 {
        let pixels = Int64(asset.pixelSize.width) * Int64(asset.pixelSize.height)
        return max(0, pixels * 2)
    }
}
