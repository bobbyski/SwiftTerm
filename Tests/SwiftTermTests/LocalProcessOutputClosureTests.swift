// Gated like LocalProcess itself: there is no process to spawn on iOS.
#if !os(iOS) && !os(Windows)
import XCTest
import Foundation
@testable import SwiftTerm

/// Output closure must follow every queued byte, independent of process exit.
final class LocalProcessOutputClosureTests: XCTestCase, LocalProcessDelegate {
    private var received: [UInt8] = []
    private var closed = false
    private var closeCount = 0
    private var exitEvent: XCTestExpectation?

    func testPTYClosureFollowsLargeFinalOutput() {
        let closure = expectation(description: "PTY output closed")
        let termination = expectation(description: "Process exit")
        exitEvent = termination
        let process = LocalProcess(delegate: self)
        process.onOutputClosed = { error in
            XCTAssertTrue(error == 0 || error == EIO, "Unexpected PTY error: \(error)")
            self.closed = true
            self.closeCount += 1
            closure.fulfill()
        }
        // `stty -opost` first: with the tty translating \n to \r\n, macOS
        // sometimes emits the \r twice when the pty's output queue fills, which
        // it does when a loaded machine reads slowly — "557\r\r\n", a few lines
        // in 20,000, only under the full suite. That is the kernel's line
        // discipline, not SwiftTerm, and not what this test is about, so the
        // bytes here are exactly what seq wrote.
        process.startProcess(executable: "/bin/sh", args: ["-c", "stty -opost; /usr/bin/seq 1 20000; printf FINAL; exit 7"])
        wait(for: [closure, termination], timeout: 20)
        let expected = (1...20000).map(String.init).joined(separator: "\n") + "\nFINAL"
        XCTAssertEqual(String(decoding: received, as: UTF8.self), expected)
        XCTAssertEqual(closeCount, 1)
        process.terminate()
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        XCTAssertFalse(closed, "Bytes arrived after output closure")
        received.append(contentsOf: slice)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        XCTAssertEqual(exitCode, 7)
        exitEvent?.fulfill()
    }

    func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
}

#endif
