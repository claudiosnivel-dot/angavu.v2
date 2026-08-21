import XCTest
@testable import AngavuDomain

// T-022 — AC-022-1 / AC-022-2. Banner accesso limited derivato da PhotoAccess.

private struct FakeAccessProvider: PhotoAccessProviding {
    let value: PhotoAccess
    func currentAccess() -> PhotoAccess { value }
}

final class LimitedAccessBannerTests: XCTestCase {

    // AC-022-1: PhotoAccess.limited → banner presente e totale marcato parziale.
    func test_limited_bannerPresentAndPartial() {
        let banner = DashboardBannerPolicy.banner(for: .limited)

        XCTAssertTrue(banner.showLimitedAccessBanner, "limited deve mostrare il banner")
        XCTAssertTrue(banner.isTotalPartial, "con limited il totale è parziale")
    }

    // AC-022-2: PhotoAccess.full → nessun banner e totale NON parziale.
    func test_full_noBannerNotPartial() {
        let banner = DashboardBannerPolicy.banner(for: .full)

        XCTAssertFalse(banner.showLimitedAccessBanner, "full non mostra il banner")
        XCTAssertFalse(banner.isTotalPartial, "con full il totale è completo")
    }

    // Coerenza col provider e con gli altri stati: solo limited attiva il banner.
    func test_viaProviderAndOtherStates() {
        let viaProvider = DashboardBannerPolicy.banner(from: FakeAccessProvider(value: .limited))
        XCTAssertTrue(viaProvider.showLimitedAccessBanner)
        XCTAssertTrue(viaProvider.isTotalPartial)

        for access in [PhotoAccess.denied, .notDetermined] {
            let banner = DashboardBannerPolicy.banner(for: access)
            XCTAssertFalse(banner.showLimitedAccessBanner, "\(access) non mostra il banner limited")
            XCTAssertFalse(banner.isTotalPartial, "\(access) non marca il totale parziale")
        }
    }
}
