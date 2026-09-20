import Foundation

/// A program that runs in this process and behaves like the far end of a
/// connection.
///
/// BASICStudio already drives a `VectorTerminalView` this way on macOS — text
/// in, VTG in, keystrokes back out, no pty anywhere — so this is the contract
/// it plugs into when it comes to iPad. The vocabulary is deliberately the
/// same one a remote shell has, so nothing above can tell a local program from
/// a remote one.
protocol EmbeddedProgram: AnyObject {
    /// Begin, knowing the terminal's size. Write output through `out`.
    func start(cols: Int, rows: Int, out: @escaping (String) -> Void)
    /// Bytes the user typed.
    func receive(_ bytes: ArraySlice<UInt8>)
    /// The terminal changed size.
    func resize(cols: Int, rows: Int)
    /// Ctrl-C. There is no SIGINT to send to yourself on iOS: a program that
    /// wants to be interruptible has to notice this and stop.
    func interrupt()
    /// Give up whatever the program is holding; it will not be called again.
    func stop()
}

/// A `TerminalTransport` whose far end is in this address space.
///
/// The simulated local shell. It is a conformer, not an exception: if this
/// needs a hole in the protocol, the protocol is wrong.
final class LoopbackTransport: TerminalTransport {
    var onOutput: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    private let program: EmbeddedProgram
    private var isRunning = false

    init(program: EmbeddedProgram) {
        self.program = program
    }

    func connect(cols: Int, rows: Int) {
        guard !isRunning else {
            return
        }
        isRunning = true
        onStateChange?(.connecting)
        program.start(cols: cols, rows: rows) { [weak self] text in
            // Everything the program writes goes out as bytes, exactly as a
            // socket would deliver them — including its VTG.
            self?.onOutput?(Array(text.utf8))
        }
        onStateChange?(.ready)
    }

    func disconnect() {
        guard isRunning else {
            return
        }
        isRunning = false
        program.stop()
        onStateChange?(.closed(reason: nil))
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        guard isRunning else {
            return
        }
        program.receive(bytes)
    }

    func resize(cols: Int, rows: Int) {
        guard isRunning else {
            return
        }
        program.resize(cols: cols, rows: rows)
    }

    func interrupt() {
        guard isRunning else {
            return
        }
        program.interrupt()
    }
}
