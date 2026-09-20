import Foundation

/// What a terminal session is connected to.
///
/// Deliberately not process-shaped: there is no pid, no exit status, no
/// `startShell`. On iOS every session is a connection — SSH, telnet, a raw
/// socket, or an in-process program on the near end of the same seam — and
/// the view above cannot tell which it is talking to.
///
/// This lives in the harness while its home is undecided (D2 in IPAD_PLAN.md).
/// Nothing here imports UIKit, so moving it into its own package is a file
/// move.
protocol TerminalTransport: AnyObject {
    /// Bytes arriving from the far end, on the main queue.
    var onOutput: (([UInt8]) -> Void)? { get set }
    /// Connection state, on the main queue.
    var onStateChange: ((TransportState) -> Void)? { get set }

    /// Open the connection. Idempotent.
    func connect(cols: Int, rows: Int)
    /// Close it, for good. `onStateChange` reports `.closed`.
    func disconnect()
    /// Send bytes the user typed.
    func send(_ bytes: ArraySlice<UInt8>)
    /// Tell the far end the terminal changed size.
    ///
    /// This is SIGWINCH over a pty, `window-change` over SSH, NAWS over
    /// telnet, and a method call in the same address space.
    func resize(cols: Int, rows: Int)
    /// Ctrl-C. There is no signal to send on iOS, so a transport delivers
    /// this however its far end can hear it.
    func interrupt()
}

/// Where a connection is, and why it stopped.
enum TransportState: Equatable {
    case idle
    case connecting
    case ready
    /// Closed, with something a human can read. `nil` means "as asked".
    case closed(reason: String?)
}

extension TerminalTransport {
    /// Convenience for transports and programs that produce text.
    func emit(_ text: String, to sink: (([UInt8]) -> Void)?) {
        sink?(Array(text.utf8))
    }
}
