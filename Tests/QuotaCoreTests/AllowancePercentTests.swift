import XCTest
@testable import QuotaCore

final class AllowancePercentTests: XCTestCase {
    func testTinyPositiveAllowanceNeverLooksExhausted() {
        XCTAssertEqual(AllowancePercent.display(0.01), "<1%")
        XCTAssertEqual(AllowancePercent.spoken(0.01), "Less than 1 percent")
    }
    func testAlmostFullUsageNeverLooksFullyExhausted() {
        XCTAssertEqual(AllowancePercent.display(99.99), ">99%")
        XCTAssertEqual(AllowancePercent.spoken(99.99), "More than 99 percent")
    }
    func testExactBoundariesAndOrdinaryValues() {
        XCTAssertEqual(AllowancePercent.display(0), "0%")
        XCTAssertEqual(AllowancePercent.display(100), "100%")
        XCTAssertEqual(AllowancePercent.display(42), "42%")
    }
    func testNonfiniteValuesStayUnknown() {
        XCTAssertEqual(AllowancePercent.display(.nan), "—")
        XCTAssertEqual(AllowancePercent.display(.infinity), "—")
    }
}
