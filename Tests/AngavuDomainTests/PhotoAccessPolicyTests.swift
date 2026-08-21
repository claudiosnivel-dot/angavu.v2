import XCTest
@testable import AngavuDomain

// T-010 — AC-010-1 / AC-010-2. Policy pura sull'accesso alla libreria.

private struct FakeAccessProvider: PhotoAccessProviding {
    let value: PhotoAccess
    func currentAccess() -> PhotoAccess { value }
}

final class PhotoAccessPolicyTests: XCTestCase {

    // AC-010-1: un authorizer che restituisce limited → PhotoAccess.limited e
    // conteggio marcato parziale (mai spacciato per totale).
    func test_limitedAccess_isPartialAndEnumerable() {
        let decision = PhotoAccessPolicy.decide(from: FakeAccessProvider(value: .limited))

        XCTAssertEqual(decision.access, .limited)
        XCTAssertTrue(decision.isPartialCount, "limited deve marcare il conteggio come parziale")
        XCTAssertTrue(decision.shouldEnumerate, "limited consente comunque l'enumerazione")
    }

    // AC-010-2: un authorizer che restituisce denied → PhotoAccess.denied e nessuna
    // enumerazione tentata.
    func test_deniedAccess_blocksEnumeration() {
        let decision = PhotoAccessPolicy.decide(from: FakeAccessProvider(value: .denied))

        XCTAssertEqual(decision.access, .denied)
        XCTAssertFalse(decision.shouldEnumerate, "denied non deve tentare enumerazione")
        XCTAssertFalse(decision.isPartialCount)
    }

    // Copertura degli altri stati: notDetermined non enumera; full non è parziale.
    func test_otherStates() {
        let full = PhotoAccessPolicy.decide(for: .full)
        XCTAssertTrue(full.shouldEnumerate)
        XCTAssertFalse(full.isPartialCount)

        let notDetermined = PhotoAccessPolicy.decide(for: .notDetermined)
        XCTAssertFalse(notDetermined.shouldEnumerate)
        XCTAssertFalse(notDetermined.isPartialCount)
    }
}
