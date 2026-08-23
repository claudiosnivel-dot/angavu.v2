import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-110 — AC-110-1 / AC-110-2. Composition root: i servizi arrivano dai port
// iniettati, senza singleton nascosti.

private struct FakeAuthorizer: PhotoLibraryAuthorizing {
    let access: PhotoAccess
    func currentAccess() -> PhotoAccess { access }
    func requestAccess() async -> PhotoAccess { access }
}

private struct FakeEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct FakeIndex: AssetIndexReading, AssetIndexWriting {
    let total: Int
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { [] }
    func count() throws -> Int { total }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct FakeByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .estimated(bytes: fallbackEstimate)
    }
}

private struct FakeDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

private func makeEnvironment(access: PhotoAccess, indexCount: Int) -> AppEnvironment {
    let index = FakeIndex(total: indexCount)
    return AppEnvironment(
        authorizer: FakeAuthorizer(access: access),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: FakeByteResolver(),
        deviceStorage: FakeDeviceStorage()
    )
}

final class AppEnvironmentTests: XCTestCase {

    // AC-110-1: il servizio risolto è esattamente quello iniettato (il fake
    // authorizer restituisce il suo valore, non un default nascosto).
    func test_resolvesInjectedServiceNotHiddenDefault() {
        let env = makeEnvironment(access: .limited, indexCount: 0)
        XCTAssertEqual(env.authorizer.currentAccess(), .limited)
    }

    // AC-110-2: il repository dell'indice è un valore conforme al port
    // AssetIndexReading del Domain (Features dipende solo dai port).
    func test_indexIsResolvedThroughDomainPort() throws {
        let env = makeEnvironment(access: .full, indexCount: 42)
        let reader: any AssetIndexReading = env.indexReader
        XCTAssertEqual(try reader.count(), 42)
    }
}
