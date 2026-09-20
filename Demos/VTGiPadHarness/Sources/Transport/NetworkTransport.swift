import Foundation
import Network

/// A TCP connection as a terminal transport: raw, or speaking telnet.
///
/// `SwiftTerm3270/Apple/TN3270Connection.swift` is the model — NWConnection,
/// optional TLS, protocol behaviour kept out of the socket. This is the same
/// shape for a VT rather than a 3270, and it is the transport that proves the
/// seam is not shaped around the in-process case: the view above cannot tell
/// this from `LoopbackTransport`.
final class NetworkTransport: TerminalTransport {
    enum Kind {
        /// Bytes through, untouched. What `nc` talks to.
        case raw
        /// Telnet NVT: IAC handled, terminal type and window size answered.
        case telnet
    }

    var onOutput: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let kind: Kind
    private let useTLS: Bool
    private let queue = DispatchQueue(label: "vtg.network-transport")
    private var connection: NWConnection?
    private var codec = TelnetCodec()

    init(host: String, port: UInt16, kind: Kind = .telnet, useTLS: Bool = false) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 23
        self.kind = kind
        self.useTLS = useTLS
    }

    // MARK: - TerminalTransport

    func connect(cols: Int, rows: Int) {
        guard connection == nil else {
            return
        }
        codec.cols = cols
        codec.rows = rows

        let parameters: NWParameters = useTLS ? .tls : .tcp
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .preparing, .setup:
                self.report(.connecting)
            case .ready:
                self.report(.ready)
                self.receiveNext()
            case .waiting(let error):
                // Reachable but not answering — a tablet changes networks
                // mid-session, so this is ordinary rather than fatal.
                self.report(.connecting)
                print("network transport waiting: \(error)")
            case .failed(let error):
                self.report(.closed(reason: "\(error)"))
                self.connection = nil
            case .cancelled:
                self.report(.closed(reason: nil))
                self.connection = nil
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        let outgoing = kind == .telnet ? codec.encode(bytes) : Array(bytes)
        write(outgoing)
    }

    func resize(cols: Int, rows: Int) {
        codec.cols = cols
        codec.rows = rows
        guard kind == .telnet else {
            return
        }
        write(codec.windowSize(cols: cols, rows: rows))
    }

    /// There is no signal to send down a socket: Ctrl-C is a byte, and the
    /// program on the far end is the one that decides what it means.
    func interrupt() {
        write([0x03])
    }

    // MARK: - Plumbing

    private func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, let connection else {
            return
        }
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            if let error {
                print("network transport send failed: \(error)")
            }
        })
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.deliver(Array(content)[...])
            }
            if isComplete {
                self.report(.closed(reason: "the far end closed the connection"))
                self.connection = nil
                return
            }
            if let error {
                self.report(.closed(reason: "\(error)"))
                self.connection = nil
                return
            }
            self.receiveNext()
        }
    }

    private func deliver(_ bytes: ArraySlice<UInt8>) {
        switch kind {
        case .raw:
            let data = Array(bytes)
            DispatchQueue.main.async { self.onOutput?(data) }
        case .telnet:
            // The codec answers negotiation itself: there is one sensible
            // reply to each of these for a terminal, and the view above has
            // no opinion about any of them.
            let (data, reply) = codec.receive(bytes)
            write(reply)
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self.onOutput?(data) }
        }
    }

    private func report(_ state: TransportState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }
}
