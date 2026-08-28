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

/// Risultato per-asset già risolto UNA volta: dimensioni (per l'aggregazione), byte
/// device best-effort (per il fallback del recuperabile) e item da sondare per la
/// residenza precisa. Separare la risoluzione (fase pesante, per-asset via PhotoKit)
/// dalla finalizzazione (aritmetica pura) permette di riportare il progresso durante
/// la sola parte lunga e di riusare gli stessi byte per aggregazione e residenza,
/// senza iterare la libreria più volte del necessario.
struct ResolvedLibrary: Equatable {
    let sized: [SizedAsset]
    let deleted: [DeletedAssetSize]
    let probeItems: [ResidencyProbeItem]
    let access: PhotoAccess
}

/// Accumulatore a RIFERIMENTO della risoluzione per-asset: evita la copia
/// copy-on-write dell'array che un fold per valore farebbe a ogni elemento (O(N²) su
/// ~25k foto — la causa reale del freeze del bugfix on-device). `ChunkedAnalysis`
/// richiede `Result: Equatable` ma non confronta MAI i risultati durante `run`,
/// quindi l'uguaglianza per identità è sufficiente e onesta.
private final class ResolveSink: Equatable {
    var sized: [SizedAsset] = []
    var deleted: [DeletedAssetSize] = []
    var probeItems: [ResidencyProbeItem] = []
    func reserveCapacity(_ minimumCapacity: Int) {
        sized.reserveCapacity(minimumCapacity)
        deleted.reserveCapacity(minimumCapacity)
        probeItems.reserveCapacity(minimumCapacity)
    }
    static func == (lhs: ResolveSink, rhs: ResolveSink) -> Bool { lhs === rhs }
}

extension DashboardScreen {
    /// Compone la schermata dashboard dai numeri veri, senza coniare tipi nuovi.
    /// Unico posto in cui `LibraryFigures` diventa `DashboardScreen`, condiviso dal
    /// flusso di scansione (che la calcola e la cacha) e dal `DashboardViewModel`.
    init(figures: LibraryFigures) {
        self.init(
            categories: figures.aggregate.categories,
            reclaimable: figures.reclaimable,
            banner: DashboardBannerPolicy.banner(for: figures.access)
        )
    }
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
        // P0-2/P0-3 + FSE-G1 (strategia B): la policy della residenza è il punto di
        // decisione unico. Numero device SOLO da misura reale e completa; misura
        // incompleta ⇒ caveat; misura assente ⇒ rispetta la determinabilità dell'ambiente
        // (optimize off = device==libreria; optimize on = caveat, finché il passo
        // differito non porta la misura reale). Mai un numero gonfiato ("139 GB su 128").
        let reclaimable = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: measuredResidency,
            from: deleted,
            optimizeStorage: environment.deviceStorage.optimizeStorageStatus(),
            deviceCapacity: environment.deviceCapacity.deviceCapacity(),
            residencyDeterminate: environment.deviceStorage.residencyIsDeterminate()
        )

        return LibraryFigures(
            aggregate: aggregate,
            reclaimable: reclaimable,
            access: environment.authorizer.currentAccess()
        )
    }

    /// Risolve i byte veri per-asset A BLOCCHI, riportando il progresso e onorando la
    /// cancellazione fra un blocco e l'altro (motore T-004). È la fase pesante della
    /// scansione unificata: per ogni asset legge il byte reale dietro il port (una
    /// chiamata PhotoKit sul device) UNA volta e la riusa per aggregazione, fallback
    /// del recuperabile e input della residenza. Il chiamante la mette off-main; su
    /// ~25k asset lo stop resta reattivo grazie ai checkpoint fra i blocchi.
    static func resolve(
        from environment: AppEnvironment,
        chunkSize: Int = 256,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<ResolvedLibrary> {
        let assets: [LibraryAsset]
        do {
            assets = try environment.indexReader.assets(matching: .all)
        } catch {
            return .failed(
                reason: AnalysisFailure(String(describing: error)),
                at: AnalysisProgress(processed: 0, total: 0)
            )
        }

        let sink = ResolveSink()
        sink.reserveCapacity(assets.count)
        let engine = ChunkedAnalysis<LibraryAsset, ResolveSink>(
            chunkSize: chunkSize,
            initial: sink
        ) { box, asset in
            let size = environment.byteResolver.byteSize(
                forLocalIdentifier: asset.id,
                fallbackEstimate: fallbackEstimate(for: asset)
            )
            let libraryBytes = size.bytes
            box.sized.append(SizedAsset(asset: asset, size: size))
            box.deleted.append(DeletedAssetSize(
                libraryBytes: libraryBytes,
                deviceResidentBytes: environment.deviceStorage.deviceResidentBytes(
                    forLocalIdentifier: asset.id,
                    libraryBytes: libraryBytes
                )
            ))
            box.probeItems.append(ResidencyProbeItem(id: asset.id, libraryBytes: libraryBytes))
            return box
        }

        switch engine.run(over: assets, cancellation: cancellation, progress: progress) {
        case .completed(let box):
            return .completed(ResolvedLibrary(
                sized: box.sized,
                deleted: box.deleted,
                probeItems: box.probeItems,
                access: environment.authorizer.currentAccess()
            ))
        case .cancelled(let at):
            return .cancelled(at: at)
        case .failed(let reason, let at):
            return .failed(reason: reason, at: at)
        }
    }

    /// Finalizza i numeri veri dai per-asset già risolti: aritmetica pura (aggregazione
    /// + recuperabile col caveat iCloud/tetto di realtà), nessuna I/O per-asset qui.
    /// `measuredResidency` reale e completa ⇒ numero device preciso (P0-2b); altrimenti
    /// caveat onesto (P0-3).
    static func figures(
        from resolved: ResolvedLibrary,
        environment: AppEnvironment,
        measuredResidency: ResidencyMeasurement? = nil
    ) -> LibraryFigures {
        let aggregate = DashboardAggregator.aggregate(resolved.sized)
        // FSE-G1 (strategia B): policy della residenza come punto di decisione unico
        // (vedi `read`). Numero device solo da misura reale e completa; altrimenti caveat.
        let reclaimable = ResidencyPolicy.reclaimable(
            strategy: .deferred,
            measurement: measuredResidency,
            from: resolved.deleted,
            optimizeStorage: environment.deviceStorage.optimizeStorageStatus(),
            deviceCapacity: environment.deviceCapacity.deviceCapacity(),
            residencyDeterminate: environment.deviceStorage.residencyIsDeterminate()
        )
        return LibraryFigures(aggregate: aggregate, reclaimable: reclaimable, access: resolved.access)
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
