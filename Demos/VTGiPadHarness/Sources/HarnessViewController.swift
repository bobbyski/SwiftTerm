import UIKit
import SwiftTerm

/// Shows a `VectorTerminalView` and either replays a scene into it or connects
/// it to a transport.
///
/// Everything the terminal shows arrives through `feed(byteArray:)` — the same
/// path a socket, an SSH channel or a recorded stream would use — and anything
/// typed leaves through the delegate's `send(source:data:)`. That is the whole
/// point of the harness: on iOS there is no process to attach to, so the view
/// has to be good enough to drive from bytes alone.
final class HarnessViewController: UIViewController {
    private let terminalView = VectorTerminalView(frame: .zero, font: nil)
    private let picker = UISegmentedControl(items: ["Text", "Graphics", "Page", "Shell", "Remote"])

    /// Set while the Shell tab is up; nil while a scene is on screen.
    private var transport: TerminalTransport?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.terminalDelegate = self
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(tabChanged), for: .valueChanged)

        view.addSubview(terminalView)
        view.addSubview(picker)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            picker.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            terminalView.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            terminalView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])

        // With no process, VTG replies have nowhere to go by default. Print
        // them, and hand them to the far end when there is one: a query that
        // answers here is a query that will answer over SSH.
        terminalView.vtgResponseHandler = { [weak self] response in
            print("harness reply: \(response.replacingOccurrences(of: "\u{1b}", with: "^["))")
            self?.transport?.send(ArraySlice(Array(response.utf8)))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let terminal = terminalView.getTerminal()
        print("harness: view \(terminalView.bounds.size), grid \(terminal.cols)x\(terminal.rows), "
              + "cell \(terminalView.currentVTGCellSize().map { "\($0.width)x\($0.height)" } ?? "unknown")")
        show(tab: 0)
    }

    @objc private func tabChanged() {
        show(tab: picker.selectedSegmentIndex)
    }

    // MARK: - Tabs

    private func show(tab: Int) {
        // Leave page mode and clear first, so tabs cannot accumulate state —
        // the same reset a host performs when a program exits.
        transport?.disconnect()
        transport = nil

        // Show or dismiss the keyboard *first*. It resizes the terminal, and
        // SwiftTerm's reflow pulls lines back out of the scrollback as it
        // does — so clearing before the resize leaves the previous tab's text
        // on screen.
        if tab >= 3 {
            _ = terminalView.becomeFirstResponder()
        } else {
            _ = terminalView.resignFirstResponder()
        }
        feed(HarnessScenes.reset)

        switch tab {
        case 1:
            feed(HarnessScenes.graphics)
        case 2:
            feed(HarnessScenes.page)
        case 3:
            startShell()
        case 4:
            startRemote()
        default:
            feed(HarnessScenes.text)
        }
        dumpFirstLines(tab)
    }

    /// Connect the terminal to an in-process program through the same seam an
    /// SSH session will use.
    private func startShell() {
        let terminal = terminalView.getTerminal()
        let loopback = LoopbackTransport(program: SimulatedShell())
        loopback.onOutput = { [weak self] bytes in
            self?.terminalView.feed(byteArray: ArraySlice(bytes))
        }
        loopback.onStateChange = { state in
            print("harness transport: \(state)")
        }
        transport = loopback
        loopback.connect(cols: terminal.cols, rows: terminal.rows)
    }

    /// Connect to a socket. Same seam, a different conformer — which is the
    /// point of the seam: nothing above this method changes.
    ///
    /// `Tools/vtg-telnet-server.py` is what this expects to find, and an iOS
    /// simulator reaches the host Mac's loopback directly.
    private func startRemote() {
        let terminal = terminalView.getTerminal()
        let network = NetworkTransport(host: Self.remoteHost, port: Self.remotePort, kind: .telnet)
        network.onOutput = { [weak self] bytes in
            self?.terminalView.feed(byteArray: ArraySlice(bytes))
        }
        network.onStateChange = { [weak self] state in
            guard let self else { return }
            print("harness transport: \(state)")
            switch state {
            case .connecting:
                self.feed("Connecting to \(Self.remoteHost):\(Self.remotePort)…\r\n")
            case .closed(let reason):
                self.feed("\r\n\u{1b}[31mDisconnected\u{1b}[0m\(reason.map { ": \($0)" } ?? "").\r\n"
                          + "Start the test server: python3 Tools/vtg-telnet-server.py\r\n")
            case .idle, .ready:
                break
            }
        }
        transport = network
        network.connect(cols: terminal.cols, rows: terminal.rows)
    }

    /// What the terminal buffer holds, so "the text is missing" can be told
    /// apart from "the text was never parsed". This is how the opaque-overlay
    /// bug was narrowed down.
    private func dumpFirstLines(_ tab: Int) {
        let terminal = terminalView.getTerminal()
        let text = terminal.getText(
            start: Position(col: 0, row: 0),
            end: Position(col: terminal.cols - 1, row: 4)
        )
        print("harness tab \(tab): buffer rows 0-4 = \(text.debugDescription)")
    }

    /// Where the Remote tab connects. The simulator's loopback is the Mac's.
    private static let remoteHost = "127.0.0.1"
    private static let remotePort: UInt16 = 2323

    private func feed(_ text: String) {
        terminalView.feed(byteArray: Array(text.utf8)[...])
    }
}

// MARK: - TerminalViewDelegate

extension HarnessViewController: TerminalViewDelegate {
    /// Keystrokes leave here. With a transport they reach the far end; with a
    /// scene on screen there is nobody to send them to.
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        transport?.send(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // SIGWINCH over a pty, window-change over SSH, a method call here.
        transport?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
