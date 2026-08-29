import AngavuDomain

// FSE-I1 (wiring) — Coordinatore del ripristino al lancio.
//
// Seam TESTABILE tra la policy pura (`LaunchRestorePolicy`, Domain) e la View
// (`HomeView`, SwiftUI, compilata-non-testata L-COL-006): consulta l'indice persistito
// dietro il port `AssetIndexReading` e restituisce la decisione. Così l'oracolo copre la
// LOGICA di ripristino senza toccare SwiftUI.
//
// Onestà: una lettura dell'indice fallita → `.fresh`, mai un ripristino su dati che non
// si riescono a leggere. Il ripristino non produce numeri qui: la dashboard, atterrando,
// li LEGGE FRESCHI dall'indice persistito (la cache in memoria sopra le view non
// sopravvive al cold relaunch), col caveat device finché la residenza non è misurata.
public struct LaunchRestoreCoordinator {
    private let indexReader: any AssetIndexReading

    public init(indexReader: any AssetIndexReading) {
        self.indexReader = indexReader
    }

    /// Comodità: costruisce dal grafo di dipendenze iniettato (nessun singleton nascosto).
    public init(environment: AppEnvironment) {
        self.init(indexReader: environment.indexReader)
    }

    /// Decisione di lancio dall'indice persistito. Un errore di lettura è trattato come
    /// «nessun dato» (conteggio 0) → `.fresh`: si scansiona, non si ripristina su dati
    /// illeggibili.
    public func decision() -> LaunchDecision {
        LaunchRestorePolicy.decide(indexedCount: indexedCount())
    }

    /// FSE-J4 — Conteggio dell'indice persistito, alla stessa condizione d'onestà della
    /// `decision()`: una lettura fallita conta 0 (mai un ripristino su dati illeggibili).
    /// Alimenta la `ScenePhaseRestorePolicy` alle transizioni del ciclo di vita.
    public func indexedCount() -> Int {
        (try? indexReader.count()) ?? 0
    }
}
