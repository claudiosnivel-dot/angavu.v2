import Foundation

// T-011 — Modello di dominio dell'asset di libreria e mapping dagli item enumerati.
//
// `LibraryAsset` è puro: nessun tipo di Photos. L'adapter del Data layer produce
// `RawEnumeratedAsset` (valori grezzi, già estratti dai PHAsset) e il Domain li
// mappa in `LibraryAsset`, filtrando i tipi non gestiti. Il mapping di grandi
// librerie riusa il motore cancellabile (T-004): stop cooperativo, niente
// eterno 0%, dieta a blocchi.

/// Tipo di media gestito dall'app. I media non foto/video vengono scartati.
public enum MediaKind: String, Equatable, Sendable, Codable {
    case photo
    case video
}

/// Sottotipi utili per le categorie del cuore-foto (screenshot, live, ecc.).
public enum AssetSubtype: String, Equatable, Sendable, Codable, CaseIterable {
    case screenshot
    case livePhoto
}

/// Dimensioni in pixel di un asset.
public struct PixelSize: Equatable, Sendable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

/// Asset della libreria, normalizzato e indipendente dalla piattaforma.
public struct LibraryAsset: Equatable, Sendable, Identifiable {
    /// Identificatore locale stabile (in PhotoKit: `PHAsset.localIdentifier`).
    public let id: String
    public let kind: MediaKind
    public let pixelSize: PixelSize
    public let creationDate: Date?
    public let subtypes: Set<AssetSubtype>

    public init(
        id: String,
        kind: MediaKind,
        pixelSize: PixelSize,
        creationDate: Date?,
        subtypes: Set<AssetSubtype>
    ) {
        self.id = id
        self.kind = kind
        self.pixelSize = pixelSize
        self.creationDate = creationDate
        self.subtypes = subtypes
    }
}

/// Item grezzo prodotto dall'enumerator del Data layer: valori già estratti dal
/// PHAsset, senza alcun tipo di Photos, così il Domain resta puro e testabile.
public struct RawEnumeratedAsset: Equatable, Sendable {
    public let localIdentifier: String
    /// Raw value di `PHAssetMediaType`: 1 = image, 2 = video (altri = non gestito).
    public let mediaTypeRawValue: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationDate: Date?
    public let isScreenshot: Bool
    public let isLivePhoto: Bool

    public init(
        localIdentifier: String,
        mediaTypeRawValue: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        isScreenshot: Bool,
        isLivePhoto: Bool
    ) {
        self.localIdentifier = localIdentifier
        self.mediaTypeRawValue = mediaTypeRawValue
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
    }
}

/// Mapping puro da item grezzi a `LibraryAsset`.
public enum LibraryAssetMapper {
    /// Raw value di `PHAssetMediaType.image`.
    static let mediaTypeImage = 1
    /// Raw value di `PHAssetMediaType.video`.
    static let mediaTypeVideo = 2

    /// Mappa un singolo item. Restituisce `nil` per i tipi non gestiti (audio,
    /// sconosciuti): non vengono indicizzati.
    public static func map(_ raw: RawEnumeratedAsset) -> LibraryAsset? {
        let kind: MediaKind
        switch raw.mediaTypeRawValue {
        case mediaTypeImage: kind = .photo
        case mediaTypeVideo: kind = .video
        default: return nil
        }

        var subtypes: Set<AssetSubtype> = []
        // I sottotipi screenshot/live valgono solo per le foto.
        if kind == .photo {
            if raw.isScreenshot { subtypes.insert(.screenshot) }
            if raw.isLivePhoto { subtypes.insert(.livePhoto) }
        }

        return LibraryAsset(
            id: raw.localIdentifier,
            kind: kind,
            pixelSize: PixelSize(width: raw.pixelWidth, height: raw.pixelHeight),
            creationDate: raw.creationDate,
            subtypes: subtypes
        )
    }

    /// Mappa un intero batch a blocchi, cancellabile (T-004). Su cancellazione a
    /// metà, gli item dei blocchi successivi non vengono mappati.
    public static func mapBatch(
        _ raws: [RawEnumeratedAsset],
        chunkSize: Int = 256,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in }
    ) -> AnalysisOutcome<[LibraryAsset]> {
        let engine = ChunkedAnalysis<RawEnumeratedAsset, [LibraryAsset]>(
            chunkSize: chunkSize,
            initial: []
        ) { acc, raw in
            var next = acc
            if let asset = map(raw) { next.append(asset) }
            return next
        }
        return engine.run(over: raws, cancellation: cancellation, progress: progress)
    }
}
