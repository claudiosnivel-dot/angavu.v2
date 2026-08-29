import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// FSE-A1 — Oracolo della strumentazione di misura.
//
// La PERFORMANCE non è oracolabile in CI (L-COL-006): qui si prova solo la LOGICA
// della telemetria, non la velocità.
//   • AC-FSE-A1-1: attraversando le fasi, ognuna apre e chiude ESATTAMENTE un
//     intervallo — contatore pari, nessun orfano, nessuna sovrapposizione.
//   • AC-FSE-A1-2: il subscriber MetricKit è registrato UNA SOLA VOLTA (idempotente),
//     a prescindere da quante volte si chiama `registerOnce()`.
// L'emissione reale (`OSSignposter`, `MXMetricManager`) è compilata-ma-non-coperta e
// si valida on-device col protocollo Instruments (§7).

// MARK: - Fake signpost che registra begin/end

private final class RecordingSignpost: ScanSignposting {
    enum Event: Equatable {
        case begin(ScanSignpostPhase)
        case end(ScanSignpostPhase)
    }

    private(set) var events: [Event] = []

    func begin(_ phase: ScanSignpostPhase) -> ScanSignpostInterval {
        events.append(.begin(phase))
        return Interval(phase: phase, owner: self)
    }

    fileprivate func recordEnd(_ phase: ScanSignpostPhase) {
        events.append(.end(phase))
    }

    private final class Interval: ScanSignpostInterval {
        private let phase: ScanSignpostPhase
        private weak var owner: RecordingSignpost?
        private var ended = false

        init(phase: ScanSignpostPhase, owner: RecordingSignpost) {
            self.phase = phase
            self.owner = owner
        }

        func end() {
            guard !ended else { return }
            ended = true
            owner?.recordEnd(phase)
        }
    }
}

// MARK: - Doppie minime dell'ambiente

private struct StubAuthorizer: PhotoLibraryAuthorizing {
    let access: PhotoAccess
    func currentAccess() -> PhotoAccess { access }
    func requestAccess() async -> PhotoAccess { access }
}

private struct StubEnumerator: PhotoAssetEnumerating {
    let raws: [RawEnumeratedAsset]
    func enumerateRawAssets() -> [RawEnumeratedAsset] { raws }
}

private final class RecordingIndex: AssetIndexReading, AssetIndexWriting {
    private(set) var upserted: [LibraryAsset] = []
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { upserted }
    func count() throws -> Int { upserted.count }
    func upsert(_ assets: [LibraryAsset]) throws { upserted.append(contentsOf: assets) }
    func remove(ids: [String]) throws {}
}

private struct StubByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .estimated(bytes: fallbackEstimate)
    }
}

private struct StubDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

private func photo(_ id: String) -> RawEnumeratedAsset {
    RawEnumeratedAsset(
        localIdentifier: id,
        mediaTypeRawValue: 1,
        pixelWidth: 100,
        pixelHeight: 100,
        creationDate: nil,
        isScreenshot: false,
        isLivePhoto: false
    )
}

private func makeEnv(access: PhotoAccess, raws: [RawEnumeratedAsset], index: RecordingIndex) -> AppEnvironment {
    AppEnvironment(
        authorizer: StubAuthorizer(access: access),
        enumerator: StubEnumerator(raws: raws),
        indexReader: index,
        indexWriter: index,
        byteResolver: StubByteResolver(),
        deviceStorage: StubDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

// MARK: - Test

final class ScanSignpostTests: XCTestCase {

    /// Ordine atteso delle fasi in una scansione completa, ognuna aperta e poi chiusa
    /// prima della successiva (nessuna sovrapposizione). FSE-F1 estende la scansione
    /// unificata alle fasi dei rilevatori (allineamento 1:1 con la barra). FSE-G1
    /// (strategia B): la MISURA della residenza (`measuringDeviceSpace`) è uscita dalla
    /// barra (differita), quindi non compare nella sequenza.
    ///
    /// FSE-H4: i rilevatori per-foto (simili, sfocate) — resi a memoria limitata da
    /// FSE-H (dHash+BK-tree, autoreleasepool) — tornano EAGER nella scansione, quindi
    /// eseguono lavoro reale e riemettono il loro intervallo signpost. La sequenza copre
    /// di nuovo TUTTE le categorie (7 fasi: indice, byte, + 5 rilevatori).
    private let expectedPhases: [ScanSignpostPhase] = [
        .indexing, .resolvingSizes,
        .analyzingScreenshots, .analyzingExactDuplicates, .analyzingSimilarPhotos,
        .analyzingBlurryPhotos, .analyzingLargeOldVideos
    ]

    // AC-FSE-A1-1: ogni fase apre e chiude esattamente un intervallo, in ordine,
    // senza orfani né sovrapposizioni.
    func test_completedScan_eachPhaseOpensAndClosesExactlyOneInterval() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A"), photo("B")], index: index)
        let signpost = RecordingSignpost()
        let vm = ScanViewModel(environment: env, signpost: signpost)

        _ = await vm.run(cancellation: CancellationToken())

        // Sequenza esatta: begin/end per ciascuna fase, in ordine.
        let expected: [RecordingSignpost.Event] = expectedPhases.flatMap { [.begin($0), .end($0)] }
        XCTAssertEqual(signpost.events, expected)

        // Invarianti d'onestà della telemetria, indipendenti dall'uguaglianza esatta:
        assertBalancedNoOrphans(signpost.events)
    }

    // Anche una scansione CANCELLATA prima della fine non lascia intervalli orfani:
    // la fase in cui cade la cancellazione si chiude comunque (via `measure`/`defer`).
    func test_cancelledScan_noOrphanIntervals() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .full, raws: [photo("A"), photo("B"), photo("C")], index: index)
        let signpost = RecordingSignpost()
        let vm = ScanViewModel(environment: env, signpost: signpost)

        let token = CancellationToken()
        token.cancel()
        _ = await vm.run(cancellation: token)

        // La fase indexing è aperta e chiusa comunque; nessun begin resta senza end.
        XCTAssertEqual(signpost.events.first, .begin(.indexing))
        assertBalancedNoOrphans(signpost.events)
    }

    // Accesso negato: la scansione fallisce prima di qualunque fase → nessun
    // intervallo aperto (niente telemetria fabbricata su lavoro mai iniziato).
    func test_deniedAccess_opensNoInterval() async {
        let index = RecordingIndex()
        let env = makeEnv(access: .denied, raws: [photo("A")], index: index)
        let signpost = RecordingSignpost()
        let vm = ScanViewModel(environment: env, signpost: signpost)

        _ = await vm.run(cancellation: CancellationToken())

        XCTAssertTrue(signpost.events.isEmpty)
    }

    // AC-FSE-A1-2: il registrar MetricKit registra una sola volta, idempotente.
    func test_metricKitRegistrar_registersExactlyOnce() {
        var registerCount = 0
        let registrar = MetricKitRegistrar { registerCount += 1 }

        XCTAssertFalse(registrar.isRegistered)
        registrar.registerOnce()
        registrar.registerOnce()
        registrar.registerOnce()

        XCTAssertEqual(registerCount, 1, "il subscriber va aggiunto una sola volta")
        XCTAssertTrue(registrar.isRegistered)
    }

    // Il registrar non registra nulla se `registerOnce()` non è mai chiamato: nessun
    // effetto collaterale alla sola costruzione.
    func test_metricKitRegistrar_noRegistrationUntilCalled() {
        var registerCount = 0
        let registrar = MetricKitRegistrar { registerCount += 1 }

        XCTAssertEqual(registerCount, 0)
        XCTAssertFalse(registrar.isRegistered)
    }

    // MARK: helper

    /// Prova che ogni `begin` ha un `end` corrispondente e che gli intervalli non si
    /// sovrappongono (un `begin` è sempre seguito dal proprio `end` prima di un altro
    /// `begin`): nessun orfano, contatore pari.
    private func assertBalancedNoOrphans(
        _ events: [RecordingSignpost.Event],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var open: ScanSignpostPhase?
        for event in events {
            switch event {
            case .begin(let phase):
                XCTAssertNil(open, "intervallo \(phase) aperto mentre \(String(describing: open)) è ancora aperto",
                             file: file, line: line)
                open = phase
            case .end(let phase):
                XCTAssertEqual(open, phase, "chiusura di \(phase) senza apertura corrispondente",
                               file: file, line: line)
                open = nil
            }
        }
        XCTAssertNil(open, "intervallo \(String(describing: open)) rimasto orfano (aperto e mai chiuso)",
                     file: file, line: line)
    }
}
