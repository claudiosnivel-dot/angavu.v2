import Foundation

// FSE-A1 — Registrazione idempotente del subscriber MetricKit.
//
// MetricKit (`MXMetricManager`) raccoglie IN CAMPO, sui device reali, i payload di
// performance (i signpost delle fasi FSE-A1, hang, picchi di memoria): è così che
// una regressione di velocità si nota senza un profiling manuale ogni volta.
//
// L'invariante: il subscriber va aggiunto UNA SOLA VOLTA, all'avvio dell'app — mai
// in una schermata secondaria, dove una ricomparsa lo re-registrerebbe (payload
// duplicati). Questo tipo rende quell'invariante TESTABILE senza MetricKit: la
// logica del "una volta sola" è pura; l'aggancio reale a `MXMetricManager` è
// iniettato come closure (compilato-ma-non-coperto, §7).
//
// Onestà/privacy: MetricKit è telemetria di sistema aggregata di Apple, on-device;
// nessun dato utente lascia il telefono per opera nostra, zero rete propria.

/// Registra un subscriber esattamente una volta. Chiamate ripetute a `registerOnce()`
/// sono no-op: idempotente per costruzione (AC-FSE-A1-2).
public final class MetricKitRegistrar {
    private let register: () -> Void
    private var didRegister = false

    /// - Parameter register: l'effetto reale (es. `MXMetricManager.shared.add(sub)`),
    ///   iniettato così che l'idempotenza sia provabile con un fake che conta le
    ///   invocazioni.
    public init(register: @escaping () -> Void) {
        self.register = register
    }

    /// Esegue la registrazione la PRIMA volta; ogni chiamata successiva è ignorata.
    public func registerOnce() {
        guard !didRegister else { return }
        didRegister = true
        register()
    }

    /// Vero dopo la prima registrazione. Espone lo stato per test e diagnostica.
    public var isRegistered: Bool { didRegister }
}
