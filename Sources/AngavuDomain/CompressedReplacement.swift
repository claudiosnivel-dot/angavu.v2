import Foundation

// T-082 — Sostituzione dell'originale con la versione compressa, solo dopo che
// l'export è verificato integro E l'anteprima è confermata. L'eliminazione
// dell'originale passa SEMPRE dal DeletionFlow (T-050) → Eliminati di recente.
//
// Nessuna perdita di dati per costruzione: se manca la verifica o la conferma, la
// sostituzione è rifiutata e l'originale resta invariato.

/// Versione compressa pronta all'indicizzazione.
public struct CompressedVideo: Equatable, Sendable {
    public let outputBytes: Int64
    public let metadata: VideoMetadata

    public init(outputBytes: Int64, metadata: VideoMetadata) {
        self.outputBytes = max(0, outputBytes)
        self.metadata = metadata
    }
}

/// Perché una sostituzione è stata rifiutata.
public enum ReplacementError: Equatable, Sendable, Error {
    /// L'export non è success o non è stato verificato integro.
    case exportNotVerified
    /// L'anteprima non è stata confermata dall'utente.
    case previewNotConfirmed
}

/// Piano di sostituzione approvato: cosa indicizzare e come eliminare l'originale.
/// Il `deletion` è un `DeletionFlow` già portato a `confirmed` sull'originale, così
/// l'eliminazione passa dalla rete di sicurezza (mai un delete diretto).
public struct CompressedReplacement: Equatable, Sendable {
    public let originalId: String
    public let compressed: CompressedVideo
    public let deletion: DeletionFlow

    public init(originalId: String, compressed: CompressedVideo, deletion: DeletionFlow) {
        self.originalId = originalId
        self.compressed = compressed
        self.deletion = deletion
    }
}

/// Pianificatore puro della sostituzione.
public enum CompressedReplacementPlanner {
    /// Approva la sostituzione SOLO se: l'export è `success` **e** verificato
    /// integro, **e** l'anteprima è confermata. Altrimenti rifiuta senza toccare
    /// l'originale.
    ///
    /// In caso di approvazione, l'originale viene instradato al `DeletionFlow`
    /// (preview → accept → confirm) su `[originalId]`, così l'eliminazione resta
    /// dietro il gate della rete di sicurezza.
    public static func plan(
        outcome: VideoExportOutcome,
        exportVerifiedIntegral: Bool,
        previewConfirmed: Bool,
        originalId: String
    ) -> Result<CompressedReplacement, ReplacementError> {
        guard previewConfirmed else { return .failure(.previewNotConfirmed) }
        guard case .success(let outputBytes, _, let metadata) = outcome, exportVerifiedIntegral else {
            return .failure(.exportNotVerified)
        }

        var deletion = DeletionFlow()
        deletion.presentPreview(for: [originalId])
        deletion.acceptPreview()
        deletion.confirm()

        let replacement = CompressedReplacement(
            originalId: originalId,
            compressed: CompressedVideo(outputBytes: outputBytes, metadata: metadata),
            deletion: deletion
        )
        return .success(replacement)
    }
}
