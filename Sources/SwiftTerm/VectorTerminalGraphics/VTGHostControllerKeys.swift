import Foundation

/// VTG `keyEvents`: a program that asked is told each key going down and
/// coming up, beside the bytes the key types (VGT-11).
extension VTGHostController {
    /// The `key` message for a transition, or nil when it is not to be sent:
    /// the view does not deliver keys, the program has not asked, the host is
    /// muted — the terminal's own shell is back in front, and must never
    /// receive these — or it is a repeat the program did not ask for.
    public func keyResponse(_ transition: VTGKeyTransition) -> String? {
        guard deliversKeyEvents, sendsKeyEvents, !isMuted else {
            return nil
        }
        if transition.kind == .repeat, !reportsKeyRepeats {
            return nil
        }
        return VTGResponseEncoder.key(transition)
    }

    /// Answers `keyEvents,enabled=…[,repeat=1]`. Refused, and said so to a
    /// program that asked for refusals, where the view cannot deliver keys.
    func keyEventsResponses(_ command: VectorTerminalGraphicsCommand, enabled: Bool) -> [String] {
        guard deliversKeyEvents else {
            sendsKeyEvents = false
            guard enabled, sendsErrorEvents else { return [] }
            return [VTGResponseEncoder.apc("commandRejected", [
                ("command", command.name),
                ("id", ""),
                ("reason", "unsupported"),
            ])]
        }
        sendsKeyEvents = enabled
        reportsKeyRepeats = enabled && ["1", "true", "yes", "on"].contains(command.parameters["repeat"]?.lowercased() ?? "")
        return []
    }

    /// The command list for `capabilities`: `keyEvents` only where keys are
    /// delivered, so a program never waits on events that cannot come.
    var advertisedCommands: [String] {
        VTGResponseEncoder.defaultCommands + (deliversKeyEvents ? ["keyEvents"] : [])
    }

    var advertisedEvents: [String] {
        VTGResponseEncoder.defaultEvents + (deliversKeyEvents ? ["key"] : [])
    }
}
