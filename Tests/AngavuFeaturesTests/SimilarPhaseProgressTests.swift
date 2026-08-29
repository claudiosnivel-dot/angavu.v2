import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-I2 (AC-FSE-I2-2) — Oracolo del progresso della fase «foto simili».
//
// La fase ha due sotto-fasi costose per-foto: composizione dHash (una decodifica per
// foto) e keep-best (il quality scorer per membro di cluster). Prima di FSE-I2 solo la
// composizione riportava progresso: la barra toccava N/N e RESTAVA FERMA per tutto il
// keep-best (il ~1 min osservato al 2° device-test). Qui si verifica che la sequenza di
// progresso emessa da `similarPhotosReview` sia monotòna non decrescente FINO al
// completamento, SENZA un tratto finale a progresso fermo e senza frazioni fabbricate
// (ogni unità è una foto composta o un membro realmente scorato).
//
// È logica PURA (fake dietro i port, nessun device): il calcolo reale di dHash/qualità
// resta compilato-non-testato sul device (L-COL-006).

// MARK: - Fake dei port (minimi per la fase simili)

private struct SPAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct SPEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct SPIndex: AssetIndexReading, AssetIndexWriting {
    let assetsToReturn: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { assetsToReturn }
    func count() throws -> Int { assetsToReturn.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct SPByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .estimated(bytes: fallbackEstimate)
    }
}

private struct SPDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

private struct SPPerceptualHasher: AssetPerceptualHashing {
    let dHashById: [String: UInt64]
    func dHash(for asset: LibraryAsset) -> UInt64? { dHashById[asset.id] }
}

private struct SPQuality: QualityScoring {
    let sharpnessById: [String: Double]
    func score(for asset: LibraryAsset) throws -> QualityScore {
        QualityScore(sharpness: sharpnessById[asset.id] ?? 0, faceQuality: nil, aesthetics: nil)
    }
}

private func spPhoto(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: nil, subtypes: [])
}

private func spEnvironment(
    assets: [LibraryAsset],
    dHashById: [String: UInt64],
    qualityById: [String: Double]
) -> AppEnvironment {
    let index = SPIndex(assetsToReturn: assets)
    return AppEnvironment(
        authorizer: SPAuthorizer(),
        enumerator: SPEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: SPByteResolver(),
        deviceStorage: SPDeviceStorage(),
        perceptualHasher: SPPerceptualHasher(dHashById: dHashById),
        qualityScorer: SPQuality(sharpnessById: qualityById),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

// MARK: - Test

final class SimilarPhaseProgressTests: XCTestCase {

    /// Scenario: 5 foto, di cui 3 (P1,P2,P3) formano UN cluster reale (dHash vicini) e 2
    /// (P4,P5) restano singleton (dHash lontani). Il keep-best gira quindi su 3 membri.
    private func run() throws -> (progresses: [AnalysisProgress], review: CategoryReview) {
        let env = spEnvironment(
            assets: [spPhoto("P1"), spPhoto("P2"), spPhoto("P3"), spPhoto("P4"), spPhoto("P5")],
            dHashById: [
                "P1": 0x0000_0000_0000_0000,
                "P2": 0x0000_0000_0000_0001,   // 1 bit da P1 → simili
                "P3": 0x0000_0000_0000_0003,   // 2 bit da P1 → simili
                "P4": 0xFFFF_FFFF_FFFF_FFFF,   // 64 bit da P1 → singleton
                "P5": 0xFFFF_FFFF_0000_0000    // 32 bit da P1 e da P4 → singleton
            ],
            qualityById: ["P1": 0.9, "P2": 0.5, "P3": 0.1]
        )
        var progresses: [AnalysisProgress] = []
        let data = try CategoryReviewSource.reviewData(for: .similarPhotos, from: env) {
            progresses.append($0)
        }
        return (progresses, data.review)
    }

    // Ancora di scenario: il keep-best ha effettivamente girato su un cluster reale.
    func test_scenario_producesRealClusterProposal() throws {
        let (_, review) = try run()
        XCTAssertEqual(review.keepIds, ["P1"], "si tiene la più nitida del cluster")
        XCTAssertEqual(Set(review.removableIds), ["P2", "P3"], "gli altri due simili sono removable")
    }

    // AC-FSE-I2-2 — la sequenza di progresso è monotòna non decrescente.
    func test_progress_isMonotonicNonDecreasing() throws {
        let (progresses, _) = try run()
        XCTAssertFalse(progresses.isEmpty, "la fase emette progresso, mai muta")
        var previous = 0.0
        for step in progresses {
            XCTAssertGreaterThanOrEqual(
                step.fraction, previous - 1e-9,
                "frazione mai in calo (composizione → keep-best)"
            )
            previous = step.fraction
        }
    }

    // AC-FSE-I2-2 — raggiunge il completamento (1.0) e SOLO alla fine: nessun tratto
    // finale a progresso fermo. Prima di FSE-I2 la composizione toccava N/N (1.0) e la
    // barra restava lì per tutto il keep-best; ora il 100% avviene una volta sola, in coda.
    func test_progress_reachesCompletionOnlyAtEnd() throws {
        let (progresses, _) = try run()
        XCTAssertEqual(progresses.last?.fraction, 1.0, "l'ultimo passo è il completamento")
        XCTAssertTrue(
            progresses.dropLast().allSatisfy { $0.fraction < 1.0 },
            "il 100% non è mai raggiunto prima della fine (niente barra ferma a N/N)"
        )
        XCTAssertEqual(
            progresses.filter { $0.fraction >= 1.0 }.count, 1,
            "il completamento è un evento unico, non un tratto finale fermo"
        )
    }

    // AC-FSE-I2-2 — il keep-best fa AVANZARE la barra: esiste almeno un evento con
    // frazione strettamente fra la fine della composizione (headroom a 0.5) e 1.0. È la
    // prova che, dopo la composizione, la barra si muove mentre gira il quality scorer.
    func test_progress_advancesDuringKeepBest() throws {
        let (progresses, _) = try run()
        XCTAssertTrue(
            progresses.contains { $0.fraction > 0.5 && $0.fraction < 1.0 },
            "un evento di keep-best avanza la barra oltre l'headroom della composizione"
        )
        // La composizione riserva l'headroom: la sua fine (senza keep-best) non supera 0.5.
        XCTAssertTrue(
            progresses.contains { abs($0.fraction - 0.5) < 1e-9 },
            "la composizione finisce a metà barra, lasciando spazio al keep-best"
        )
    }
}
