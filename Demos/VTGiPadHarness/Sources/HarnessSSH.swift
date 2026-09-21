import UIKit
import TerminalTransports

/// The SSH tab: ask for a login, check the host key, connect.
///
/// Credentials are typed by the person using the harness and never stored.
/// Host keys are remembered in `UserDefaults` through `SSHKnownHosts` — keys
/// are public, so that is an acceptable home for them; passwords are not.
@MainActor
enum HarnessSSH {
    private static let knownHostsKey = "harness.knownHosts"

    /// Ask for host, user and password, then hand back a transport to connect.
    static func askForLogin(
        from controller: UIViewController,
        connect: @escaping (SSHTransport) -> Void
    ) {
        let alert = UIAlertController(
            title: "SSH",
            message: "The simulator reaches this Mac's loopback, so 127.0.0.1 is the Mac (with Remote Login on).",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "host[:port]"
            field.text = "127.0.0.1"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "user"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "password"
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak alert] _ in
            let fields = alert?.textFields ?? []
            let address = fields[0].text ?? ""
            let parts = address.split(separator: ":")
            let host = parts.first.map(String.init) ?? "127.0.0.1"
            let port = parts.count > 1 ? Int(parts[1]) ?? 22 : 22
            let credentials = SSHCredentials(
                username: fields[1].text ?? "",
                method: .password(fields[2].text ?? "")
            )
            let transport = SSHTransport(host: host, port: port, credentials: credentials)
            transport.hostKeyValidator = { [weak controller] key, decide in
                guard let controller else { return decide(false) }
                validate(key, from: controller, decide: decide)
            }
            connect(transport)
        })
        controller.present(alert, animated: true)
    }

    /// Trust on first use, remembered; a changed key is shown, never waved through.
    private static func validate(
        _ key: SSHHostKey,
        from controller: UIViewController,
        decide: @escaping (Bool) -> Void
    ) {
        var known = loadKnownHosts()
        let verdict = known.check(key)
        if verdict == .trusted {
            return decide(true)
        }
        let message: String
        switch verdict {
        case .changed:
            message = "THE HOST KEY HAS CHANGED since you last connected. That is a reinstalled server — "
                + "or someone in the middle.\n\n\(readable(key.fingerprint))"
        default:
            message = "First connection to \(key.host):\(key.port). Is this its key?\n\n\(readable(key.fingerprint))"
        }
        let alert = UIAlertController(title: "Host key", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Don't connect", style: .cancel) { _ in decide(false) })
        alert.addAction(UIAlertAction(title: "Trust", style: verdict == .unknown ? .default : .destructive) { _ in
            known.trust(key)
            saveKnownHosts(known)
            decide(true)
        })
        controller.present(alert, animated: true)
    }

    /// The fingerprint in groups, so the alert wraps at a space.
    ///
    /// Left whole, UIKit hyphenates it to fit — and a hyphen that is not in
    /// the fingerprint is the last thing a person comparing fingerprints
    /// needs. The first run showed `…Gnnt-f4Yy…` for a key with no hyphen.
    private static func readable(_ fingerprint: String) -> String {
        guard let colon = fingerprint.firstIndex(of: ":") else { return fingerprint }
        let prefix = fingerprint[...colon]
        let digest = Array(fingerprint[fingerprint.index(after: colon)...])
        let groups = stride(from: 0, to: digest.count, by: 11).map {
            String(digest[$0..<min($0 + 11, digest.count)])
        }
        return prefix + "\n" + groups.joined(separator: " ") + "\n(spaces added for reading)"
    }

    private static func loadKnownHosts() -> SSHKnownHosts {
        guard let data = UserDefaults.standard.data(forKey: knownHostsKey),
              let hosts = try? JSONDecoder().decode(SSHKnownHosts.self, from: data) else {
            return SSHKnownHosts()
        }
        return hosts
    }

    private static func saveKnownHosts(_ hosts: SSHKnownHosts) {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: knownHostsKey)
        }
    }
}
