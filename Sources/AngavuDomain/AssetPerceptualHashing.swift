import Foundation

// FSE-H2 (Domain) — Port del dHash percettivo per-asset + composizione dei candidati.
//
// FSE-H1 ha portato il clustering dei simili a MEMORIA LIMITATA (BK-tree sui dHash a
// 64 bit, `SimilarClustering.clustersByHash`). FSE-H2 cabla il dHash REALE: qui vive il
// port (esagonale, come `FeaturePrinting`/`QualityScoring`) e la composizione pura dei
// candidati. L'implementazione reale (miniatura C1 `.pixels(64)` → dHash) vive nel Data.
//
// Il dHash diventa il PERCORSO PRINCIPALE dei simili (memoria O(1) per foto: solo un
// intero a 64 bit trattenuto, mai un feature print Vision). Il feature print Vision è
// demoto a conferma opzionale delle sole coppie borderline (mai il percorso principale),
// così sparisce la ritenzione O(N) di osservazioni Vision che causava il jetsam.
//
// Altitudine (00-INDEX §1bis): Domain puro — solo Foundation, nessun tipo di piattaforma.
// Il dHash arriva come `UInt64` opaco; il calcolo dai pixel vive nel Data.

/// Port del dHash percettivo di un asset (architettura esagonale). L'implementazione
/// reale (miniatura on-device → riduzione a 9×8 grigi → 64 bit) vive nel Data layer.
public protocol AssetPerceptualHashing {
    /// dHash percettivo a 64 bit dell'asset, o `nil` se non calcolabile on-device
    /// (originale solo in iCloud con rete disabilitata, decodifica fallita). Mai un
    /// valore fabbricato: un asset senza dHash resterà singleton nel clustering
    /// (`clustersByHash`), mai dichiarato simile per costruzione — nessun falso "via
    /// libera" su ciò che non è verificabile (manifesto §6).
    func dHash(for asset: LibraryAsset) -> UInt64?
}

/// Composizione PURA dei candidati alla review dei simili col dHash REALE.
///
/// È il punto in cui gli asset diventano `SimilarityCandidate` col loro dHash (non più
/// `nil` come nel cablaggio C-1): un candidato porta il dHash SOLO quando il port lo
/// produce, altrimenti `nil` (mai fabbricato, AC-FSE-H2-1). Il calcolo per-asset gira
/// sul motore per-item iniettabile (`PerItemAnalysis`, default seriale a blocchi): è la
/// fase costosa (una decodifica piccola per foto), quindi riporta progresso monotòno ed
/// è cancellabile — mai un "0% infinito", mai un lavoro non interrompibile. La memoria
/// resta limitata: si trattiene solo un `UInt64` per candidato, mai un'immagine né un
/// feature print (la dieta che rende i simili re-includibili nella scansione, FSE-H4).
public enum SimilarCandidateComposition {
    /// Compone i candidati calcolando il dHash reale di ogni foto dietro il port.
    /// L'ordine d'INPUT è preservato (deterministico); l'esito è sempre esplicito
    /// (`completed | cancelled | failed`) col progresso raggiunto.
    public static func candidates(
        for photos: [LibraryAsset],
        hashing: any AssetPerceptualHashing,
        analysis: PerItemAnalysis = .serial(),
        cancellation: CancellationToken = CancellationToken(),
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<[SimilarityCandidate]> {
        analysis.map(photos, cancellation: cancellation, progress: progress) { asset in
            SimilarityCandidate(asset: asset, dHash: hashing.dHash(for: asset))
        }
    }
}
