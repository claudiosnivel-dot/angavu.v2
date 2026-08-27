// FSE-A1 — Telemetria a livello d'app.
//
// Possiede il subscriber MetricKit e lo registra UNA SOLA VOLTA all'avvio (mai in
// una schermata secondaria, dove una ricomparsa lo re-registrerebbe). È ritenuto
// dall'`AngavuApp` per l'intera vita del processo: MetricKit tiene i subscriber e
// serve una reference forte lato app.
//
// Confine onesto (L-COL-006): la registrazione reale a `MXMetricManager` è
// device-only (compilata-ma-non-coperta, §7); l'INVARIANTE di idempotenza è provata
// dall'oracolo su `MetricKitRegistrar` in `ScanSignpostTests`.
//
// Privacy: MetricKit è telemetria di sistema aggregata di Apple, on-device; i
// payload non sono trasmessi né esportati da noi (zero rete propria).
import AngavuFeatures
#if canImport(MetricKit)
import MetricKit
#endif

final class AppTelemetry {
    private let registrar: MetricKitRegistrar
    #if canImport(MetricKit)
    private let subscriber = AngavuMetricSubscriber()
    #endif

    init() {
        #if canImport(MetricKit)
        let sub = subscriber
        registrar = MetricKitRegistrar {
            MXMetricManager.shared.add(sub)
        }
        #else
        registrar = MetricKitRegistrar(register: {})
        #endif
        registrar.registerOnce()
    }
}

#if canImport(MetricKit)
/// Subscriber MetricKit: riceve in campo i payload metrici/diagnostici. Non li
/// esporta né li trasmette (zero rete): sono per la diagnosi on-device. Nessun dato
/// utente è elaborato qui.
final class AngavuMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {}

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {}
}
#endif
