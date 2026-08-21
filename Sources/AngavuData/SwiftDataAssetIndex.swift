import AngavuDomain
import Foundation

// T-012 (Data) — Indice SwiftData della libreria.
//
// `AssetRecord` è il modello persistito, con `id` univoco. `SwiftDataAssetIndex`
// implementa i port `AssetIndexReading`/`AssetIndexWriting` del Domain con upsert
// idempotente per id. Interamente on-device (zero backend). SwiftData è Apple-only:
// tutto guardato da `canImport(SwiftData)`; su Linux il file compila a vuoto,
// preservando altitudine e build.

#if canImport(SwiftData)
import SwiftData

/// Record persistito dell'indice. `id` univoco → l'upsert non può duplicare.
///
/// `byteCount`/`byteCountIsExact` sono popolati da un passaggio di dimensionamento
/// successivo (T-014 fornisce il modello `ByteSize`); default 0 = ancora ignoto.
@available(macOS 14, iOS 17, *)
@Model
public final class AssetRecord {
    @Attribute(.unique) public var id: String
    public var kindRaw: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var creationDate: Date?
    public var isScreenshot: Bool
    public var isLivePhoto: Bool
    public var byteCount: Int64
    public var byteCountIsExact: Bool

    public init(
        id: String,
        kindRaw: String,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        isScreenshot: Bool,
        isLivePhoto: Bool,
        byteCount: Int64 = 0,
        byteCountIsExact: Bool = false
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
        self.byteCount = byteCount
        self.byteCountIsExact = byteCountIsExact
    }
}

@available(macOS 14, iOS 17, *)
extension AssetRecord {
    /// Crea un record dai campi indicizzabili di un `LibraryAsset`.
    convenience init(asset: LibraryAsset) {
        self.init(
            id: asset.id,
            kindRaw: asset.kind.rawValue,
            pixelWidth: asset.pixelSize.width,
            pixelHeight: asset.pixelSize.height,
            creationDate: asset.creationDate,
            isScreenshot: asset.subtypes.contains(.screenshot),
            isLivePhoto: asset.subtypes.contains(.livePhoto)
        )
    }

    /// Aggiorna i campi indicizzabili in place, preservando le dimensioni in byte
    /// (che appartengono a un passaggio separato).
    func apply(_ asset: LibraryAsset) {
        kindRaw = asset.kind.rawValue
        pixelWidth = asset.pixelSize.width
        pixelHeight = asset.pixelSize.height
        creationDate = asset.creationDate
        isScreenshot = asset.subtypes.contains(.screenshot)
        isLivePhoto = asset.subtypes.contains(.livePhoto)
    }

    /// Ricostruisce il modello di dominio dal record.
    func toLibraryAsset() -> LibraryAsset {
        var subtypes: Set<AssetSubtype> = []
        if isScreenshot { subtypes.insert(.screenshot) }
        if isLivePhoto { subtypes.insert(.livePhoto) }
        return LibraryAsset(
            id: id,
            kind: MediaKind(rawValue: kindRaw) ?? .photo,
            pixelSize: PixelSize(width: pixelWidth, height: pixelHeight),
            creationDate: creationDate,
            subtypes: subtypes
        )
    }
}

/// Repository SwiftData dell'indice.
@available(macOS 14, iOS 17, *)
public final class SwiftDataAssetIndex: AssetIndexReading, AssetIndexWriting {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Scrittura

    public func upsert(_ assets: [LibraryAsset]) throws {
        for asset in assets {
            let targetId = asset.id
            var descriptor = FetchDescriptor<AssetRecord>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.apply(asset)          // aggiornamento in place per id
            } else {
                context.insert(AssetRecord(asset: asset))
            }
        }
        try context.save()
    }

    public func remove(ids: [String]) throws {
        for targetId in ids {
            var descriptor = FetchDescriptor<AssetRecord>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1
            if let record = try context.fetch(descriptor).first {
                context.delete(record)
            }
        }
        try context.save()
    }

    // MARK: Lettura

    public func assets(matching query: AssetQuery) throws -> [LibraryAsset] {
        var descriptor = FetchDescriptor<AssetRecord>()
        // Filtro per tipo direttamente nel fetch (indicizzabile da SwiftData).
        if let kind = query.kind {
            let kindRaw = kind.rawValue
            descriptor.predicate = #Predicate { $0.kindRaw == kindRaw }
        }
        var records = try context.fetch(descriptor)

        // Filtri numerici/temporali applicati in memoria: predicati opzionali
        // compositi sono fragili col macro #Predicate; qui restano semplici e
        // corretti.
        if let minBytes = query.minBytes {
            records = records.filter { $0.byteCount >= minBytes }
        }
        if let olderThan = query.olderThan {
            records = records.filter { record in
                guard let created = record.creationDate else { return false }
                return created < olderThan
            }
        }

        return records.map { $0.toLibraryAsset() }
    }

    public func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<AssetRecord>())
    }
}
#endif
