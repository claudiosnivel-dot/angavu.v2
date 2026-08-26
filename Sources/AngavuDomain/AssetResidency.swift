import Foundation

// P0-2b — Residenza per-asset reale (numero device preciso). Cuore PURO.
//
// Problema (device-test, POST-DEVICE-UX-PLAN §P0-2b): con iCloud "Ottimizza spazio"
// attivo NON sappiamo, a buon mercato, quanti byte di ogni originale sono davvero
// sul telefono ORA. Finché non lo sappiamo, la dashboard mostra un CAVEAT (mai un
// numero gonfiato — il bug "139 GB su un 128 GB"). P0-2b introduce un probe
// per-asset (adapter PhotoKit, device-only) e QUI la logica pura che lo aggrega in
// modo onesto, cancellabile e testabile senza device.
//
// Invarianti di onestà (oracolo di dominio):
//  • per-asset i byte device non superano MAI i byte libreria (l'originale non può
//    occupare sul telefono più di quanto pesa in libreria);
//  • un originale non servibile offline conta 0 byte device (è in cloud, non libera
//    spazio locale eliminandolo);
//  • la misura è "determinata" SOLO quando il probe ha coperto TUTTI gli asset; su
//    cancellazione o errore resta indeterminata → la presentazione torna al caveat,
//    mai un numero parziale spacciato per totale.
//
// Altitudine: nessun import di PhotoKit. Il probe è un port (protocollo) iniettato;
// l'adapter reale vive nel Data (`PHAssetResidencyProbe`). Il motore è
// `ChunkedAnalysis` (T-004): a blocchi, cancellabile, così il chiamante lo mette
// off-main su ~25k asset senza rifreezare la UI.

/// Port di misura della residenza per-asset. **Sincrono di proposito**: si compone
/// col motore `ChunkedAnalysis` (sincrono) che il chiamante esegue off-main;
/// l'adapter reale attende in modo bloccante la richiesta async di PhotoKit su quel
/// thread di fondo. Contratto d'onestà del ritorno: byte residenti sul device ORA,
/// `>= 0`, `<= libraryBytes`; `0` quando l'originale non è servibile senza rete.
public protocol AssetResidencyProbing {
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64
}

/// Asset da sondare: identificatore + byte libreria (il tetto d'onestà per-asset).
public struct ResidencyProbeItem: Equatable, Sendable {
    public let id: String
    public let libraryBytes: Int64

    public init(id: String, libraryBytes: Int64) {
        self.id = id
        self.libraryBytes = max(0, libraryBytes)
    }
}

/// Misura aggregata della residenza sul device. `isDeterminate` è vero SOLO quando
/// il probe ha coperto tutti gli asset (`coveredCount == totalCount`): solo allora
/// `deviceResidentBytes` è un numero reale utilizzabile; altrimenti la presentazione
/// mostra un caveat (manifesto: mai un numero device fabbricato o parziale).
public struct ResidencyMeasurement: Equatable, Sendable {
    /// Somma dei byte residenti sul device misurati (0 quando indeterminata).
    public let deviceResidentBytes: Int64
    /// Somma dei byte libreria degli asset coperti.
    public let libraryBytes: Int64
    /// Quanti asset il probe ha effettivamente misurato.
    public let coveredCount: Int
    /// Quanti asset erano da misurare in totale.
    public let totalCount: Int

    public init(deviceResidentBytes: Int64, libraryBytes: Int64, coveredCount: Int, totalCount: Int) {
        let total = max(0, totalCount)
        let library = max(0, libraryBytes)
        self.totalCount = total
        self.libraryBytes = library
        self.coveredCount = min(max(0, coveredCount), total)
        // Invariante d'onestà: i byte device non superano quelli libreria.
        self.deviceResidentBytes = min(library, max(0, deviceResidentBytes))
    }

    /// Vero quando il probe ha coperto ogni asset: la misura è affidabile e la
    /// dashboard può mostrare i byte device reali invece del caveat. Una libreria
    /// vuota (`totalCount == 0`) è banalmente determinata (0 byte, nulla da misurare).
    public var isDeterminate: Bool { coveredCount == totalCount }

    /// Misura indeterminata (nessun numero device affidabile) che porta con sé quanti
    /// asset erano stati coperti prima dello stop: usata su cancellazione/errore.
    public static func indeterminate(coveredCount: Int, totalCount: Int) -> ResidencyMeasurement {
        // covered forzato sotto total così `isDeterminate` resta falso anche se il
        // progresso segnasse "tutti processati" a fronte di un esito non-completed.
        let total = max(0, totalCount)
        let covered = min(max(0, coveredCount), max(0, total - 1))
        return ResidencyMeasurement(
            deviceResidentBytes: 0,
            libraryBytes: 0,
            coveredCount: covered,
            totalCount: total
        )
    }
}

/// Aggregatore puro della residenza per-asset, sul motore cancellabile a blocchi.
public enum ResidencyAggregator {
    /// Accumulatore interno del fold: byte device, byte libreria, asset coperti.
    struct Accumulator: Equatable {
        var deviceBytes: Int64
        var libraryBytes: Int64
        var covered: Int
    }

    /// Sonda ogni asset a blocchi cancellabili e restituisce un esito esplicito.
    ///  • `.completed(measurement)` con `isDeterminate == true`: numero device reale;
    ///  • `.cancelled`/`.failed` → misura **indeterminata** (residui non misurati,
    ///    nessun numero fabbricato), col progresso raggiunto.
    /// Il chiamante mette `run` off-main; il probe reale (device) è bloccante per
    /// asset ma i checkpoint di cancellazione fra i blocchi tengono lo stop reattivo.
    public static func measure(
        items: [ResidencyProbeItem],
        probe: any AssetResidencyProbing,
        chunkSize: Int = 64,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<ResidencyMeasurement> {
        let total = items.count
        let engine = ChunkedAnalysis<ResidencyProbeItem, Accumulator>(
            chunkSize: chunkSize,
            initial: Accumulator(deviceBytes: 0, libraryBytes: 0, covered: 0)
        ) { acc, item in
            // Tetto d'onestà per-asset: 0…libraryBytes. L'adapter reale già rispetta
            // il contratto; qui lo si ri-vincola per non fidarsi ciecamente del port.
            let raw = probe.deviceResidentBytes(forLocalIdentifier: item.id, libraryBytes: item.libraryBytes)
            let device = min(item.libraryBytes, max(0, raw))
            return Accumulator(
                deviceBytes: acc.deviceBytes + device,
                libraryBytes: acc.libraryBytes + item.libraryBytes,
                covered: acc.covered + 1
            )
        }

        switch engine.run(over: items, cancellation: cancellation, progress: progress) {
        case .completed(let acc):
            return .completed(ResidencyMeasurement(
                deviceResidentBytes: acc.deviceBytes,
                libraryBytes: acc.libraryBytes,
                coveredCount: acc.covered,
                totalCount: total
            ))
        case .cancelled(let reached):
            // Residui non misurati: nessun numero device parziale, solo caveat.
            return .cancelled(at: reached)
        case .failed(let reason, let reached):
            return .failed(reason: reason, at: reached)
        }
    }

    /// Estrae la misura da un esito: `.completed` → la misura determinata; ogni altro
    /// esito → una misura **indeterminata** col progresso raggiunto (mai un numero).
    public static func measurement(from outcome: AnalysisOutcome<ResidencyMeasurement>) -> ResidencyMeasurement {
        switch outcome {
        case .completed(let measurement):
            return measurement
        case .cancelled(let reached), .failed(_, let reached):
            return ResidencyMeasurement.indeterminate(
                coveredCount: reached.processed,
                totalCount: reached.total
            )
        }
    }
}

/// Null-object del probe: assume ogni originale residente (byte device == libreria).
/// È un **segnaposto inerte** per costruire l'`AppEnvironment` e i test senza
/// PhotoKit; NON è la sorgente di un numero mostrato — la dashboard espone un numero
/// device solo quando una misura reale e completa arriva dall'adapter device
/// (`PHAssetResidencyProbe`). Documentato apertamente (L-COL-006).
public struct AssumeResidentResidencyProbe: AssetResidencyProbing {
    public init() {}
    public func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        max(0, libraryBytes)
    }
}
