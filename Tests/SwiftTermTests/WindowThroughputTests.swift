//
//  WindowThroughputTests.swift
//  WINDOW_PLAN.md 0.8 and 3.11 — feeding through the window router, with no
//  windows, costs what feeding the terminal directly costs.
//

import Foundation
import Testing
@testable import SwiftTerm

struct WindowThroughputTests {
    /// Colored output, the kind `ls --color` and compilers produce: lots of
    /// ESC bytes, none of them a window command.
    private func sample() -> [UInt8] {
        let esc = "\u{1b}"
        let line = "\(esc)[32mok\(esc)[0m  file-\(String(repeating: "x", count: 50)).swift \(esc)[1;34m12345\(esc)[0m\r\n"
        return Array(String(repeating: line, count: 20_000).utf8)
    }

    @Test("Rule 5: with no window, the router costs nothing measurable")
    func routerThroughput() {
        let bytes = sample()
        let chunks = stride(from: 0, to: bytes.count, by: 4096).map { bytes[$0..<min(bytes.count, $0 + 4096)] }
        func time(_ body: () -> Void) -> Double {
            let started = ProcessInfo.processInfo.systemUptime
            body()
            return ProcessInfo.processInfo.systemUptime - started
        }
        // Warm up, then take the best of three for each.
        var direct = Double.infinity, routed = Double.infinity
        for _ in 0..<3 {
            let terminal = TerminalTestHarness.makeTerminal(cols: 120, rows: 40).terminal
            direct = min(direct, time { for chunk in chunks { terminal.feed(buffer: chunk) } })
            let routedTerminal = TerminalTestHarness.makeTerminal(cols: 120, rows: 40).terminal
            let manager = VTGWindowManager(cellSize: { (8, 16) }, send: { _ in }, processRunning: { true })
            routed = min(routed, time { for chunk in chunks { manager.feed(chunk) { routedTerminal.feed(buffer: $0) } } })
        }
        let megabytes = Double(bytes.count) / 1_048_576
        print(String(format: "0.8/3.11: %.1f MB — direct %.1f MB/s, routed %.1f MB/s (%.1f%% slower)",
                     megabytes, megabytes / direct, megabytes / routed, (routed / direct - 1) * 100))
        // A generous bound for a debug build on a busy machine; the printed
        // numbers are the record.
        #expect(routed < direct * 1.15)
    }
}
