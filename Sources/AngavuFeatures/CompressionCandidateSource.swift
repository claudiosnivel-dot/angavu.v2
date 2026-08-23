import AngavuDomain

// Guscio UI — Sorgente dei candidati alla compressione: produce la lista dei
// video REALI dall'indice, dietro i port dell'AppEnvironment.
//
// ONESTÀ (L-COL-006): qui si legge SOLO ciò che l'indice sa davvero — gli asset
// `.video` col loro byte-size VERO (`AssetByteSizeResolving`, exact quando
// disponibile, altrimenti stima esplicitamente marcata). La durata e il bitrate
// (che servono alla stima del risparmio, T-080) NON sono nell'indice: si leggono
// on-device dietro `VideoSpecProviding`, mai fabbricati qui. Nessuna logica di
// dominio nuova: si riusa la stessa risoluzione byte del `LibraryFiguresReader`.
// Altitudine invariata: si legge dietro il port `AssetIndexReading`.

/// Un video candidato alla compressione, coi dati VERI noti off-device.
public struct CompressionCandidate: Equatable, Sendable, Identifiable {
    public let id: String
    /// Byte occupati dal video (fonte VERA: exact dall'indice, o stima marcata).
    public let originalBytes: Int64
    /// Vero se `originalBytes` è una stima (byte-size esatto non disponibile): va
    /// dichiarato, mai spacciato per esatto.
    public let isSizeEstimated: Bool

    public init(id: String, originalBytes: Int64, isSizeEstimated: Bool) {
        self.id = id
        self.originalBytes = originalBytes
        self.isSizeEstimated = isSizeEstimated
    }

    /// Etichetta VoiceOver UMANA della riga candidata. L'`id` è un
    /// `localIdentifier` PhotoKit (rumore per chi ascolta): resta visibile a
    /// schermo ma NON va mai letto ad alta voce.
    public var accessibilityLabel: String { "Video" }

    /// Valore VoiceOver: i byte (formattati dalla View, unica fonte del formato
    /// locale) con la marca di stima quando il byte-size non è esatto (mai una
    /// stima spacciata per esatta anche all'ascolto).
    public func accessibilityValue(formattedBytes: String) -> String {
        isSizeEstimated ? formattedBytes + ", stima" : formattedBytes
    }
}

/// Produttore dei candidati reali dall'indice. `throws`: la lettura dell'indice non
/// va mai mascherata con un verde finto (un errore è uno stato d'errore esplicito
/// nella schermata, mai una lista vuota spacciata per «nessun video»).
enum CompressionCandidateSource {
    /// Elenca i video indicizzati coi byte veri, dal più grande al più piccolo
    /// (i grandi liberano più spazio: si offrono per primi). Tie-break per id, così
    /// l'ordine è deterministico.
    static func candidates(from environment: AppEnvironment) throws -> [CompressionCandidate] {
        let assets = try environment.indexReader.assets(matching: .all)
        return assets
            .filter { $0.kind == .video }
            .map { asset -> CompressionCandidate in
                let size = environment.byteResolver.byteSize(
                    forLocalIdentifier: asset.id,
                    fallbackEstimate: LibraryFiguresReader.fallbackEstimate(for: asset)
                )
                return CompressionCandidate(
                    id: asset.id,
                    originalBytes: size.bytes,
                    isSizeEstimated: !size.isExact
                )
            }
            .sorted { lhs, rhs in
                lhs.originalBytes != rhs.originalBytes
                    ? lhs.originalBytes > rhs.originalBytes
                    : lhs.id < rhs.id
            }
    }
}
