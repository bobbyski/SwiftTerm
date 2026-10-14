#if os(macOS)
import Foundation
import XCTest
@testable import SwiftTerm

/// Fast child exits must never allow an old PTY callback to stop its successor.
final class LocalProcessReuseTests: XCTestCase, LocalProcessDelegate {
    private var remaining = 0
    private var exits: XCTestExpectation?
    private var process: LocalProcess?

    func testThirtyImmediateReplacementChildrenExitExactlyOnce() {
        remaining = 30
        let done = expectation(description: "All replacement child exits")
        done.expectedFulfillmentCount = remaining
        exits = done
        let runner = LocalProcess(delegate: self)
        process = runner
        runner.startProcess(executable: "/usr/bin/true")
        wait(for: [done], timeout: 20)
        XCTAssertEqual(remaining, 0)
        XCTAssertFalse(runner.running)
        runner.terminate()
        process = nil
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        XCTAssertEqual(exitCode, 0)
        remaining -= 1
        exits?.fulfill()
        if remaining > 0 { source.startProcess(executable: "/usr/bin/true") }
    }

    func dataReceived(slice: ArraySlice<UInt8>) { XCTAssertTrue(slice.isEmpty) }
    func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
}
#endif
