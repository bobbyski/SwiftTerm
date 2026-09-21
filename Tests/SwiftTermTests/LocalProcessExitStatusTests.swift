// Gated like LocalProcess itself: there is no process to spawn on iOS.
#if !os(iOS) && !os(Windows)
import XCTest
@testable import SwiftTerm

final class LocalProcessExitStatusTests: XCTestCase {
    func testNormalExitCodes() {
        XCTAssertEqual(LocalProcessExitStatus.decode(0), 0)
        XCTAssertEqual(LocalProcessExitStatus.decode(7 << 8), 7)
        XCTAssertEqual(LocalProcessExitStatus.decode(255 << 8), 255)
    }

    func testSignalsAndStoppedChildren() {
        XCTAssertEqual(LocalProcessExitStatus.decode(15), 143)
        XCTAssertEqual(LocalProcessExitStatus.decode(9), 137)
        XCTAssertEqual(LocalProcessExitStatus.decode(11 | 0x80), 139)
        XCTAssertNil(LocalProcessExitStatus.decode((19 << 8) | 0x7f))
    }
}

#endif
