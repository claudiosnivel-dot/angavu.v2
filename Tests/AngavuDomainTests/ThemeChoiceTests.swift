import XCTest
@testable import AngavuDomain

// Tema: la scelta persiste e degrada in sicurezza al default.

final class ThemeChoiceTests: XCTestCase {

    func test_defaultIsSystem() {
        XCTAssertEqual(ThemeChoice.fallback, .system)
        XCTAssertEqual(ThemeChoice(storageValue: nil), .system)
    }

    func test_unknownStorageFallsBackToSystem() {
        XCTAssertEqual(ThemeChoice(storageValue: "seppia"), .system)
        XCTAssertEqual(ThemeChoice(storageValue: ""), .system)
    }

    func test_roundTrip() {
        for choice in ThemeChoice.allCases {
            XCTAssertEqual(ThemeChoice(storageValue: choice.storageValue), choice)
        }
    }

    func test_hasThreeChoices() {
        XCTAssertEqual(Set(ThemeChoice.allCases), [.system, .light, .dark])
    }
}
