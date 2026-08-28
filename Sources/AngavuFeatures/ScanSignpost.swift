import AngavuDomain
import Foundation

// FSE-A1 — Strumentazione di misura delle fasi della scansione.
//
// Rende OGNI fase del motore (indice → byte per-asset → residenza device) un
// intervallo NOMINATO, così Instruments/MetricKit possono attribuirle il tempo e
// provare i guadagni delle leve FSE (protocollo §7 del FAST-SCAN-ENGINE-PLAN).
//
// Confine di verifica onesto (L-COL-002 / L-COL-006): la PERFORMANCE non è
// oracolabile in CI. Qui l'oracolo prova solo la LOGICA — che ogni fase apra e
// chiuda ESATTAMENTE un intervallo, senza orfani (AC-FSE-A1-1). L'emissione reale
// (`OSSignposter`) è compilata-ma-non-coperta: si legge in Instruments su device.
//
// Onestà/privacy (security_notes FSE-A1): i signpost non registrano MAI contenuti
// dell'utente né path — solo il nome della fase e conteggi. Zero PII, zero rete.
//
// Altitudine: `os` è un framework di sistema trasversale (telemetria), non una
// capacità-dato → sta in Features come da piano (§3), non dietro un port del Data.

/// Le fasi misurabili della scansione unificata. Nomi allineati 1:1 a
/// `ScanPipelineProgress.Stage` (la barra), così l'attribuzione dei tempi in
/// Instruments corrisponde alle fasi che l'utente vede scorrere.
public enum ScanSignpostPhase: String, CaseIterable, Sendable {
    /// Enumerazione + mapping + scrittura dell'indice.
    case indexing
    /// Risoluzione dei byte reali per-asset + aggregazione per categoria.
    case resolvingSizes
    /// Misura della residenza per-asset (spazio device liberabile ORA, P0-2b).
    /// FSE-G1 — NON è più una fase della barra unificata: la misura è differita
    /// (strategia B, `DashboardViewModel.measureResidency`). La fase resta un intervallo
    /// NOMINATO così Instruments attribuisce il tempo del passo differito on-device.
    case measuringDeviceSpace
    /// FSE-F1 — rilevatori di categoria, ognuno un intervallo NOMINATO così Instruments
    /// attribuisce il tempo alla singola categoria (i pesanti — duplicati/simili/sfocate
    /// — sono i candidati alle leve FSE).
    case analyzingScreenshots
    case analyzingExactDuplicates
    case analyzingSimilarPhotos
    case analyzingBlurryPhotos
    case analyzingLargeOldVideos

    /// Fase di misura corrispondente alla fase della barra (allineamento 1:1). Una sola
    /// fonte per la mappatura: la scansione misura ESATTAMENTE le fasi che l'utente vede.
    /// FSE-G1: `measuringDeviceSpace` non è più una fase della barra (residenza differita),
    /// quindi non ha una `Stage` di origine — resta usabile direttamente dal passo differito.
    public init(_ stage: ScanPipelineProgress.Stage) {
        switch stage {
        case .indexing: self = .indexing
        case .resolvingSizes: self = .resolvingSizes
        case .analyzingScreenshots: self = .analyzingScreenshots
        case .analyzingExactDuplicates: self = .analyzingExactDuplicates
        case .analyzingSimilarPhotos: self = .analyzingSimilarPhotos
        case .analyzingBlurryPhotos: self = .analyzingBlurryPhotos
        case .analyzingLargeOldVideos: self = .analyzingLargeOldVideos
        }
    }

    /// Nome stabile dell'intervallo per gli strumenti. `StaticString`: costante di
    /// codice, mai un dato utente.
    public var intervalName: StaticString {
        switch self {
        case .indexing: return "scan.indexing"
        case .resolvingSizes: return "scan.resolvingSizes"
        case .measuringDeviceSpace: return "scan.measuringDeviceSpace"
        case .analyzingScreenshots: return "scan.analyzingScreenshots"
        case .analyzingExactDuplicates: return "scan.analyzingExactDuplicates"
        case .analyzingSimilarPhotos: return "scan.analyzingSimilarPhotos"
        case .analyzingBlurryPhotos: return "scan.analyzingBlurryPhotos"
        case .analyzingLargeOldVideos: return "scan.analyzingLargeOldVideos"
        }
    }
}

/// Un intervallo aperto: `end()` lo chiude ESATTAMENTE una volta (idempotente sulle
/// chiamate successive), così non esistono chiusure doppie né orfani.
public protocol ScanSignpostInterval: AnyObject {
    func end()
}

/// Sorgente di intervalli di misura per fase. Iniettabile: reale in produzione,
/// fake negli oracoli (che contano begin/end per provare il bilanciamento).
public protocol ScanSignposting: AnyObject {
    func begin(_ phase: ScanSignpostPhase) -> ScanSignpostInterval
}

public extension ScanSignposting {
    /// Misura una fase attorno a `body`: apre un intervallo e lo chiude una volta
    /// sola all'uscita — anche in caso di `return`/`throw` dentro `body` — grazie al
    /// `defer`. È la SOLA via che il motore usa: rende impossibile un intervallo
    /// orfano per costruzione (AC-FSE-A1-1).
    func measure<T>(_ phase: ScanSignpostPhase, _ body: () throws -> T) rethrows -> T {
        let interval = begin(phase)
        defer { interval.end() }
        return try body()
    }
}

/// Null-object: nessuna emissione. Default quando `os` non è disponibile (CI Linux /
/// logica pura) e negli oracoli che non ispezionano la telemetria.
public final class NoOpScanSignpost: ScanSignposting {
    public init() {}

    public func begin(_ phase: ScanSignpostPhase) -> ScanSignpostInterval {
        NoOpInterval()
    }

    private final class NoOpInterval: ScanSignpostInterval {
        func end() {}
    }
}

/// Signpost di produzione: reale su Apple (`os`), altrimenti no-op. È la default di
/// `ScanViewModel`; i test iniettano un fake che registra begin/end.
public func liveScanSignpost() -> any ScanSignposting {
    #if canImport(os)
    if #available(iOS 15, macOS 12, *) {
        return OSSignpostScanSignpost()
    }
    return NoOpScanSignpost()
    #else
    return NoOpScanSignpost()
    #endif
}

#if canImport(os)
import os

/// Adapter reale: un intervallo `OSSignposter` per fase, sottosistema/categoria
/// dedicati. Compilato-ma-non-coperto (L-COL-006): il valore si legge in Instruments
/// col protocollo §7, mai in CI.
@available(iOS 15, macOS 12, *)
public final class OSSignpostScanSignpost: ScanSignposting {
    private let signposter: OSSignposter

    public init(subsystem: String = "com.angavu.scan") {
        self.signposter = OSSignposter(subsystem: subsystem, category: "scan")
    }

    public func begin(_ phase: ScanSignpostPhase) -> ScanSignpostInterval {
        let state = signposter.beginInterval(phase.intervalName)
        return Interval(signposter: signposter, name: phase.intervalName, state: state)
    }

    private final class Interval: ScanSignpostInterval {
        private let signposter: OSSignposter
        private let name: StaticString
        private let state: OSSignpostIntervalState
        private var ended = false

        init(signposter: OSSignposter, name: StaticString, state: OSSignpostIntervalState) {
            self.signposter = signposter
            self.name = name
            self.state = state
        }

        func end() {
            guard !ended else { return }
            ended = true
            signposter.endInterval(name, state)
        }
    }
}
#endif
