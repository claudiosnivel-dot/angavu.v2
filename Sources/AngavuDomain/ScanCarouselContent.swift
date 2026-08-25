import Foundation

// E-4 — Carosello "leggi mentre aspetti" come DATI (dominio puro).
//
// Durante la scansione la metà superiore ospita un carosello: manifesto Angavu +
// curiosità sullo spazio. Il contenuto è modellato come dominio puro (id stabili,
// testabile), non annegato nella View — stesso principio di `ManifestContent` (T-100).
//
// INVARIANTE DI ONESTÀ (manifesto: numeri veri): le curiosità sono APPROSSIMATIVE e
// dichiarate tali (`isApproximate == true`, copy con "circa/può/spesso/fino a"). Le
// slide-manifesto sono affermazioni precise sull'app (`isApproximate == false`). Mai
// un numero esatto inventato: le curiosità restano ordini di grandezza.

/// Natura di una slide: promessa del manifesto (precisa) o curiosità (approssimata).
public enum ScanSlideKind: String, Sendable, Equatable, Codable {
    case manifesto
    case curiosity
}

/// Identità stabile di una slide. L'oracolo asserisce per `id`, non per prosa:
/// riscrivere il testo non rompe i test, toglierne una sì.
public enum ScanSlideID: String, Sendable, Equatable, CaseIterable, Codable {
    // Manifesto (1–4)
    case onDevice
    case noAds
    case realNumbers
    case safetyNet
    // Curiosità (5–22)
    case fourKSize
    case hevcSaving
    case screenshotPng
    case duplicatesWaste
    case livePhotoWeight
    case oneGbEquivalent
    case burstShots
    case heicVsJpeg
    case panoramaWeight
    case slomoFps
    case icloudVsLibrary
    case recentlyDeleted
    case proRawProRes
    case duplicatesOrigin
    case heaviestNotBest
    case videosVsPhotos
    case screenshotClutter
    case smallGesturesBigEffect
}

/// Una slide del carosello: contenuto + SF Symbol, con la marca di approssimazione.
public struct ScanSlide: Equatable, Sendable, Identifiable {
    public let id: ScanSlideID
    public let title: String
    public let body: String
    /// Nome dell'SF Symbol (usato solo dalla View).
    public let symbol: String
    public let kind: ScanSlideKind

    public init(id: ScanSlideID, title: String, body: String, symbol: String, kind: ScanSlideKind) {
        self.id = id
        self.title = title
        self.body = body
        self.symbol = symbol
        self.kind = kind
    }

    /// Vero quando il contenuto è un ordine di grandezza, non un numero esatto: le
    /// curiosità lo sono sempre, il manifesto mai.
    public var isApproximate: Bool { kind == .curiosity }
}

/// Contenuto del carosello di scansione. Solo dati; il layout è View-level.
public struct ScanCarouselContent: Equatable, Sendable {
    public let slides: [ScanSlide]

    public init(slides: [ScanSlide]) {
        self.slides = slides
    }

    /// Id presenti (per l'oracolo).
    public var slideIDs: [ScanSlideID] { slides.map(\.id) }

    /// Le slide del manifesto, in ordine.
    public var manifestoSlides: [ScanSlide] { slides.filter { $0.kind == .manifesto } }

    /// Le curiosità, in ordine.
    public var curiositySlides: [ScanSlide] { slides.filter { $0.kind == .curiosity } }

    /// Vero se ogni curiosità è marcata approssimata e ogni manifesto no: l'invariante
    /// d'onestà del carosello (mai un numero esatto inventato spacciato per fatto).
    public var honestyInvariantHolds: Bool {
        curiositySlides.allSatisfy(\.isApproximate) && manifestoSlides.allSatisfy { !$0.isApproximate }
    }
}

// MARK: - Contenuto canonico

public extension ScanCarouselContent {
    /// Il carosello canonico: 4 slide-manifesto + 18 curiosità (ordini di grandezza,
    /// dichiarati approssimati). Rivedibile; le curiosità usano copy con "circa/può".
    static let angavu = ScanCarouselContent(slides: [
        // — Manifesto (1–4) —
        ScanSlide(id: .onDevice, title: "Tutto sul tuo telefono",
                  body: "Niente cloud, niente server: i tuoi dati non escono dal dispositivo.",
                  symbol: "iphone", kind: .manifesto),
        ScanSlide(id: .noAds, title: "Zero pubblicità",
                  body: "Nessun annuncio, nessun tracciamento. Il Pro sarà un pagamento unico, opzionale.",
                  symbol: "hand.raised", kind: .manifesto),
        ScanSlide(id: .realNumbers, title: "Numeri veri, coi caveat",
                  body: "Se un dato è una stima, te lo diciamo. Mai numeri gonfiati.",
                  symbol: "checkmark.seal", kind: .manifesto),
        ScanSlide(id: .safetyNet, title: "Rete di sicurezza",
                  body: "Niente sparisce senza la tua conferma e un'anteprima. Sempre.",
                  symbol: "arrow.uturn.backward", kind: .manifesto),
        // — Curiosità (5–22): ordini di grandezza, dichiarati approssimati —
        ScanSlide(id: .fourKSize, title: "Video 4K",
                  body: "Un minuto di 4K a 60 fps può pesare oltre 400 MB.",
                  symbol: "video", kind: .curiosity),
        ScanSlide(id: .hevcSaving, title: "HEVC",
                  body: "A parità di qualità, l'HEVC può comprimere un video fino a circa metà rispetto all'H.264.",
                  symbol: "arrow.down.right.and.arrow.up.left", kind: .curiosity),
        ScanSlide(id: .screenshotPng, title: "Screenshot",
                  body: "Uno screenshot PNG spesso pesa più di una foto compressa.",
                  symbol: "camera.viewfinder", kind: .curiosity),
        ScanSlide(id: .duplicatesWaste, title: "Copie identiche",
                  body: "Due copie identiche occupano il doppio dello spazio, con zero valore in più.",
                  symbol: "doc.on.doc", kind: .curiosity),
        ScanSlide(id: .livePhotoWeight, title: "Live Photo",
                  body: "Una Live Photo è una foto più un breve video: può pesare di più di una foto normale.",
                  symbol: "livephoto", kind: .curiosity),
        ScanSlide(id: .oneGbEquivalent, title: "Quanto è 1 GB",
                  body: "Circa 500–1000 foto compresse, o pochi minuti di 4K.",
                  symbol: "externaldrive", kind: .curiosity),
        ScanSlide(id: .burstShots, title: "Raffiche",
                  body: "Una raffica può creare decine di scatti quasi identici in un secondo.",
                  symbol: "square.stack.3d.up", kind: .curiosity),
        ScanSlide(id: .heicVsJpeg, title: "HEIC",
                  body: "A parità di qualità, un HEIC pesa circa metà di un vecchio JPEG.",
                  symbol: "photo", kind: .curiosity),
        ScanSlide(id: .panoramaWeight, title: "Panoramiche",
                  body: "Una panoramica può pesare quanto 5–10 foto normali.",
                  symbol: "pano", kind: .curiosity),
        ScanSlide(id: .slomoFps, title: "Slo-mo",
                  body: "I video slo-mo girano a 120 o 240 fps: molti più fotogrammi, più spazio.",
                  symbol: "slowmo", kind: .curiosity),
        ScanSlide(id: .icloudVsLibrary, title: "iCloud",
                  body: "Con Ottimizza iCloud gli originali possono stare nel cloud: "
                      + "\"sul telefono\" non è \"in libreria\".",
                  symbol: "icloud", kind: .curiosity),
        ScanSlide(id: .recentlyDeleted, title: "Eliminare",
                  body: "Non è per sempre: gli elementi restano in \"Eliminati di recente\" per circa 30 giorni.",
                  symbol: "trash", kind: .curiosity),
        ScanSlide(id: .proRawProRes, title: "ProRAW / ProRes",
                  body: "Sugli iPhone Pro una foto ProRAW può superare i 25 MB, e un minuto di ProRes vari GB.",
                  symbol: "camera.aperture", kind: .curiosity),
        ScanSlide(id: .duplicatesOrigin, title: "Da dove nascono i duplicati",
                  body: "Condivisioni, salvataggi e backup: spesso la stessa immagine, molte volte.",
                  symbol: "rectangle.on.rectangle", kind: .curiosity),
        ScanSlide(id: .heaviestNotBest, title: "Peso ≠ qualità",
                  body: "La foto più pesante non è la più bella: spesso è solo la meno compressa.",
                  symbol: "scalemass", kind: .curiosity),
        ScanSlide(id: .videosVsPhotos, title: "Video vs foto",
                  body: "Cancellare 10 video 4K può liberare più spazio di 5.000 foto.",
                  symbol: "film", kind: .curiosity),
        ScanSlide(id: .screenshotClutter, title: "Cartella screenshot",
                  body: "Lo screenshot è utile una volta, poi dimenticato: la cartella cresce in silenzio.",
                  symbol: "photo.stack", kind: .curiosity),
        ScanSlide(id: .smallGesturesBigEffect, title: "Piccoli gesti",
                  body: "Qualche minuto di pulizia può valere gigabyte.",
                  symbol: "sparkles", kind: .curiosity)
    ])
}
