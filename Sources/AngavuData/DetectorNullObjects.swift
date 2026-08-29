import AngavuDomain

// C-1 (Data) — Null-object dei port dei rilevatori di categoria.
//
// Servono ai default dell'`AppEnvironment` (grafi parziali/di test) e alla build su
// piattaforme dove l'adapter reale non è disponibile. Regola di onestà (L-COL-006):
// un null-object dichiara sempre "non calcolabile" — `nil` per hashing/feature print/
// nitidezza, un punteggio neutro per la qualità — così una categoria priva del
// rilevatore reale resta **vuota** anziché fabbricare candidati. Stesso idioma di
// `NoThumbnailProvider`/`UnknownDeviceCapacity`.

/// Nessun hashing di contenuto: nessun asset è verificabile come duplicato esatto.
public struct NoContentHasher: AssetContentHashing {
    public init() {}
    public func digest(for asset: LibraryAsset) throws -> AssetDigest? { nil }
}

/// FSE-H2 — Nessun dHash percettivo: ogni candidato resta senza dHash (`nil`) → il
/// clustering per vicinanza (`clustersByHash`) li lascia tutti singleton, nessuna coppia
/// dichiarata simile. Usato finché `live()` non cabla l'adapter reale (miniatura C1).
public struct NoPerceptualHasher: AssetPerceptualHashing {
    public init() {}
    public func dHash(for asset: LibraryAsset) -> UInt64? { nil }
}

/// Nessun punteggio di qualità reale: punteggio neutro (tutti i termini a zero/assenti).
/// A parità di punteggio il keep di un cluster ricade sul tie-break deterministico per
/// id (T-042): scelta stabile, mai arbitraria. Usato solo finché `live()` non cabla
/// lo scorer di Vision.
public struct NoQualityScorer: QualityScoring {
    public init() {}
    public func score(for asset: LibraryAsset) throws -> QualityScore {
        QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil)
    }
}

/// Nessun punteggio di nitidezza: `nil` = non misurabile → nessun asset è dichiarato
/// sfocato (regola di confine T-070: mai un falso positivo su ciò che non si misura).
public struct NoSharpnessScorer: SharpnessScoring {
    public init() {}
    public func sharpness(for asset: LibraryAsset) throws -> Double? { nil }
}
