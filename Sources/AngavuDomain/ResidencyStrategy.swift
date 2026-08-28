import Foundation

// FSE-G1 — Ripensamento della residenza (opzione 3, «strategia B»). Cuore PURO.
//
// Rischio introdotto in #78 (FAST-SCAN-ENGINE-PLAN §1.7): misurare la residenza
// per-asset (I/O su OGNI originale) come fase OBBLIGATORIA della scansione unificata
// è la cosa più pesante del percorso. Sul device dell'utente allunga parecchio la
// prima scansione, e non aggiunge nulla ai numeri di libreria/categoria — serve solo
// alla cifra «liberabile sul telefono ORA».
//
// Strategia B (fuori dal percorso obbligatorio): la scansione atterra in dashboard
// appena indice + numeri di categoria sono pronti, mostrando il CAVEAT device; la
// misura device reale si completa DOPO, in background (`DashboardViewModel.measureResidency`),
// e aggiorna la cifra quando — e SOLO quando — è reale e completa.
//
// Questo file è la POLICY pura che governa le due decisioni, testabile senza device:
//  1) cosa presentare (numero device reale vs caveat) data una misura eventualmente
//     assente/incompleta;
//  2) se la scansione può dichiararsi completa SENZA la residenza.
//
// Invariante di onestà ASSOLUTO (manifesto: numeri veri): un numero device solo da
// una misura REALE e COMPLETA (`ResidencyMeasurement.isDeterminate`). Ogni altro caso
// — non ancora misurata (`nil`), campione, cancellata, fallita — NON è un numero: la
// presentazione mostra il caveat, mai una cifra fabbricata o parziale.
//
// Altitudine: solo Foundation. Delega il calcolo a `ReclaimableSpaceCalculator`
// (già puro); non introduce alcuna dipendenza di piattaforma.

/// Dove misurare la residenza device rispetto al percorso di scansione.
public enum ResidencyStrategy: Equatable, Sendable {
    /// Residenza SUL percorso obbligatorio: la scansione non è completa finché la
    /// misura per-asset non è pronta (comportamento #78, pesante). Conservato per
    /// completezza e per rendere esplicita la scelta.
    case blocking
    /// Residenza FUORI dal percorso obbligatorio (strategia B): la scansione atterra
    /// col caveat appena indice + numeri di categoria sono pronti; la misura device
    /// reale si completa dopo, in background, e aggiorna la dashboard quando (e solo
    /// se) è reale e completa. Il default del prodotto.
    case deferred
}

/// Esito della decisione di policy: cosa alimentare al calcolo dello spazio e se la
/// scansione principale può chiudersi senza la residenza.
public struct ResidencyDecision: Equatable, Sendable {
    /// La misura da passare al calcolo: presente SOLO quando reale e completa
    /// (`isDeterminate`); `nil` per ogni misura assente/incompleta → il calcolo
    /// mostrerà il caveat, mai un numero fabbricato.
    public let measuredResidency: ResidencyMeasurement?
    /// Vero quando la scansione principale può dichiararsi `completed` senza aver
    /// completato la residenza (strategia `deferred`): la residenza si completa dopo,
    /// senza bloccare l'atterraggio in dashboard.
    public let scanMayCompleteWithoutResidency: Bool

    public init(measuredResidency: ResidencyMeasurement?, scanMayCompleteWithoutResidency: Bool) {
        self.measuredResidency = measuredResidency
        self.scanMayCompleteWithoutResidency = scanMayCompleteWithoutResidency
    }

    /// Vero quando si può mostrare il numero device reale (misura reale e completa).
    public var showsMeasuredDeviceSpace: Bool { measuredResidency != nil }
}

/// Policy PURA della residenza device. L'oracolo di dominio (`ResidencyStrategyTests`)
/// prova che l'onestà è invariante e che la strategia `deferred` sblocca la
/// completezza della scansione.
public enum ResidencyPolicy {
    /// Decisione pura. Regola d'onestà: usa la misura SOLO se reale e completa; ogni
    /// altra (nil/campione/cancellata/fallita) → nessun numero (caveat a valle). La
    /// strategia `deferred` consente alla scansione di chiudersi senza la residenza.
    public static func decide(
        strategy: ResidencyStrategy,
        measurement: ResidencyMeasurement?
    ) -> ResidencyDecision {
        let usable = (measurement?.isDeterminate == true) ? measurement : nil
        return ResidencyDecision(
            measuredResidency: usable,
            scanMayCompleteWithoutResidency: strategy == .deferred
        )
    }

    /// Vero quando la residenza è sul percorso obbligatorio della scansione: solo
    /// `blocking`. Con `deferred` la scansione non deve attendere la residenza
    /// (AC-FSE-G1-3). Comodità booleana speculare a `decide`.
    public static func blocksScanCompletion(_ strategy: ResidencyStrategy) -> Bool {
        strategy == .blocking
    }

    /// Applica la decisione al calcolo dello spazio recuperabile. Numero device reale
    /// SOLO da misura completa; ogni misura tentata ma incompleta forza il caveat
    /// (`deviceSpaceIsIndeterminate`), mai un numero parziale. Una misura ASSENTE
    /// (`nil`, residenza non ancora tentata) rispetta la determinabilità dell'ambiente
    /// (`residencyDeterminate`): con optimize-storage disattivo ogni originale è
    /// residente → device == libreria, numero onesto senza probe; con optimize attivo
    /// → caveat finché il passo differito non porta la misura reale.
    public static func reclaimable(
        strategy: ResidencyStrategy,
        measurement: ResidencyMeasurement?,
        from items: [DeletedAssetSize],
        optimizeStorage: ICloudOptimizeStorage,
        deviceCapacity: DeviceStorageCapacity? = nil,
        residencyDeterminate: Bool = true
    ) -> ReclaimableSpace {
        let decision = decide(strategy: strategy, measurement: measurement)
        let determinateForCalc: Bool
        if decision.showsMeasuredDeviceSpace {
            // Misura reale e completa: il numero verrà da `measuredResidency`.
            determinateForCalc = true
        } else if measurement == nil {
            // Non ancora misurata: rispetta la determinabilità dell'ambiente.
            determinateForCalc = residencyDeterminate
        } else {
            // Misura tentata ma INCOMPLETA (campione/cancellata/fallita): caveat assoluto.
            determinateForCalc = false
        }
        return ReclaimableSpaceCalculator.reclaimable(
            from: items,
            optimizeStorage: optimizeStorage,
            deviceCapacity: deviceCapacity,
            residencyDeterminate: determinateForCalc,
            measuredResidency: decision.measuredResidency
        )
    }
}
