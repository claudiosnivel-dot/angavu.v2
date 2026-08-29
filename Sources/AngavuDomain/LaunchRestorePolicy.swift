import Foundation

// FSE-I1 — Ripristino stato al lancio (correzione dal 2° device-test). Cuore PURO.
//
// Difetto osservato on-device: iOS termina l'app memory-heavy in background → al
// ritorno un COLD RELAUNCH riparte con `ScanState.idle`, e l'app costringe a una NUOVA
// scansione unificata benché l'indice SwiftData (e la cache derivata FSE-E) siano già
// su disco. La scansione è la parte pesante: rifarla a ogni relaunch è il difetto.
//
// Questa è la POLICY pura che decide, dato SOLO lo stato dell'indice persistito, se al
// lancio si RIPRISTINA (si atterra in dashboard sui numeri già indicizzati, categorie
// on-tap dalla cache/derivati FSE-E) o si parte FRESCHI (primo avvio: la prima scansione
// è necessaria). Nessuna scansione forzata quando esistono già dati reali.
//
// Onestà (manifesto: numeri veri). La policy NON produce numeri: decide solo il ramo.
// Il ripristino atterra sui numeri LETTI DALL'INDICE PERSISTITO (freschi per costruzione:
// la cache in memoria sopra le view non sopravvive al cold relaunch), col caveat device
// finché la residenza non è misurata (FSE-G1); e l'invalidazione su cambio libreria
// (FSE-E3, observer T-013) resta attiva → mai una cifra vecchia spacciata per fresca.
//
// Altitudine: solo Foundation. Nessuna dipendenza di piattaforma (l'indice è dietro il
// port `AssetIndexReading`; qui entra solo il suo conteggio, un `Int`).

/// Ramo scelto al lancio dell'app.
public enum LaunchDecision: Equatable, Sendable {
    /// Ripristina: una scansione precedente esiste (indice non vuoto) → si atterra in
    /// dashboard sui dati persistiti, senza forzare una nuova scansione. Il «Ri-scansiona»
    /// resta un'azione ESPLICITA per chi vuole rifarla davvero.
    case restore
    /// Parti freschi: nessun dato indicizzato (primo avvio) → la prima scansione è
    /// necessaria, si mostra il tasto di scansione.
    case fresh
}

/// Policy PURA del ripristino al lancio. L'oracolo di dominio (`LaunchRestorePolicyTests`)
/// prova le due direzioni: indice non vuoto → `restore`; indice vuoto → `fresh`.
public enum LaunchRestorePolicy {
    /// Decisione pura dal conteggio dell'indice persistito. Un conteggio > 0 significa
    /// «una scansione è già stata fatta»: si ripristina, mai una ri-scansione forzata.
    /// Conteggio 0 (o assenza d'indice, mappata a 0 dal chiamante): primo avvio → fresco.
    public static func decide(indexedCount: Int) -> LaunchDecision {
        indexedCount > 0 ? .restore : .fresh
    }
}
