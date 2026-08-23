import AngavuDomain
import AngavuData
import Observation

// T-111 (wiring) — Flusso di scansione come view-model osservabile.
//
// Orchestra: permessi PhotoKit → enumerazione → mapping/indicizzazione, con stato
// esplicito e stop cooperativo (motore T-004). Nessun accesso limited spacciato
// per totale: lo stato `completed` porta il flag `partialCount`. La logica sta
// dietro i port dell'AppEnvironment, quindi è testabile con fake, senza device.

/// Stato esplicito della scansione. Mai un blocco muto: ogni esito è uno di questi.
public enum ScanState: Equatable, Sendable {
    case idle
    case requestingPermission
    case scanning(AnalysisProgress)
    /// Indicizzati `indexed` asset; `partialCount` vero se l'accesso era limited.
    case completed(indexed: Int, partialCount: Bool)
    case cancelled(AnalysisProgress)
    case failed(String)
}

@Observable
public final class ScanViewModel {
    /// Messaggio di fallimento quando l'accesso alla libreria non è concesso.
    /// Esposto come costante così che la presentazione possa distinguere questo
    /// fallimento (per offrire "Apri Impostazioni") senza string-matching fragile.
    public static let accessDeniedMessage = "Accesso alla libreria non concesso."

    public private(set) var state: ScanState = .idle

    private let authorizer: any PhotoLibraryAuthorizing
    private let enumerator: any PhotoAssetEnumerating
    private let indexWriter: any AssetIndexWriting

    public init(environment: AppEnvironment) {
        self.authorizer = environment.authorizer
        self.enumerator = environment.enumerator
        self.indexWriter = environment.indexWriter
    }

    /// Esegue la scansione completa e restituisce lo stato finale. Idempotente
    /// rispetto allo stato: lo aggiorna passo per passo.
    @discardableResult
    public func run(cancellation: CancellationToken = CancellationToken()) async -> ScanState {
        state = .requestingPermission
        let access = await authorizer.requestAccess()
        let decision = PhotoAccessPolicy.decide(for: access)

        // Accesso negato / non determinato: nessuna enumerazione tentata.
        guard decision.shouldEnumerate else {
            state = .failed(Self.accessDeniedMessage)
            return state
        }

        let raws = enumerator.enumerateRawAssets()
        state = .scanning(AnalysisProgress(processed: 0, total: raws.count))

        let outcome = LibraryAssetMapper.mapBatch(raws, cancellation: cancellation) { progress in
            self.state = .scanning(progress)
        }

        switch outcome {
        case .completed(let assets):
            do {
                try indexWriter.upsert(assets)
                state = .completed(indexed: assets.count, partialCount: decision.isPartialCount)
            } catch {
                state = .failed(String(describing: error))
            }
        case .cancelled(let at):
            // Cancellata: nessuna indicizzazione dei blocchi non processati.
            state = .cancelled(at)
        case .failed(let reason, _):
            state = .failed(reason.message)
        }
        return state
    }
}
