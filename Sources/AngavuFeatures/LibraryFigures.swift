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
    ///
    /// `measuredResidency` (P0-2b): quando una misura per-asset reale e completa è
    /// disponibile (dal probe device, eseguito off-main e cachato), il device-now
    /// mostra quel numero invece del caveat. Assente/indeterminata ⇒ comportamento P0-3.
    static func read(
        from environment: AppEnvironment,
        measuredResidency: ResidencyMeasurement? = nil
    ) throws -> LibraryFigures {
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
        // P0-2/P0-3: il device-now è limitato dal tetto di realtà (capacità/spazio
        // libero del device) e, se la residenza non è determinabile, sostituito da un
        // caveat — mai un numero device gonfiato (il bug "139 GB su un 128 GB").
        let reclaimable = ReclaimableSpaceCalculator.reclaimable(
            from: deleted,
            optimizeStorage: environment.deviceStorage.optimizeStorageStatus(),
            deviceCapacity: environment.deviceCapacity.deviceCapacity(),
            residencyDeterminate: environment.deviceStorage.residencyIsDeterminate(),
            measuredResidency: measuredResidency
        )

        return LibraryFigures(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: environment.authorizer.currentAccess()
        )
    }

    /// P0-2b — Asset da sondare per la residenza (id + byte libreria), letti
    /// dall'indice e risolti coi byte reali dietro i port. È l'input del probe
    /// per-asset (`ResidencyAggregator.measure`), eseguito off-main dal chiamante.
    static func probeItems(from environment: AppEnvironment) throws -> [ResidencyProbeItem] {
        let assets = try environment.indexReader.assets(matching: .all)
        return assets.map { asset in
            let size = environment.byteResolver.byteSize(
                forLocalIdentifier: asset.id,
                fallbackEstimate: fallbackEstimate(for: asset)
            )
            return ResidencyProbeItem(id: asset.id, libraryBytes: size.bytes)
        }
    }

    /// Stima di ripiego (byte) usata SOLO quando il file-size esatto non è
    /// disponibile: il `ByteSizePolicy` la marca `estimated`, mai `exact`. Rozza,
    /// derivata dall'area in pixel (≈2 byte/pixel per un asset compresso).
    static func fallbackEstimate(for asset: LibraryAsset) -> Int64 {
        let pixels = Int64(asset.pixelSize.width) * Int64(asset.pixelSize.height)
        return max(0, pixels * 2)
    }
}
