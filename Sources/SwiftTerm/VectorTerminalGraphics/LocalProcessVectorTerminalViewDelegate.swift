#if os(macOS)
import AppKit
import Foundation

/// Delegate for ``LocalProcessVectorTerminalView`` process lifecycle events.
///
/// This mirrors `LocalProcessTerminalViewDelegate` while using
/// `LocalProcessVectorTerminalView` as the source type. Keeping it separate lets
/// existing SwiftTerm users keep their current delegates unchanged, while VTG
/// adopters get strong typing for the new drop-in view.
public protocol LocalProcessVectorTerminalViewDelegate: AnyObject {
    /// Called after the terminal grid changes size and the pseudo-terminal size
    /// has been updated for the child process.
    func sizeChanged(source: LocalProcessVectorTerminalView, newCols: Int, newRows: Int)

    /// Called when the child process requests a terminal title change.
    func setTerminalTitle(source: LocalProcessVectorTerminalView, title: String)

    /// Called when OSC 7 reports a new host current directory.
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?)

    /// Called when the child process emits BEL.
    func bell(source: TerminalView)

    /// Called when the child process exits.
    func processTerminated(source: TerminalView, exitCode: Int32?)

    /// Called when the pointer moves onto a link or leaves the current link.
    func terminalView(_ source: LocalProcessVectorTerminalView, didHoverLink link: TerminalLink?)

    /// Called when the user activates a terminal link.
    func terminalView(_ source: LocalProcessVectorTerminalView, didRequestOpenLink link: TerminalLink)
}

public extension LocalProcessVectorTerminalViewDelegate {
    /// Ignore hover changes by default.
    func terminalView(_ source: LocalProcessVectorTerminalView, didHoverLink link: TerminalLink?) {}

    /// Open activated links with the system URL handler by default.
    func terminalView(_ source: LocalProcessVectorTerminalView, didRequestOpenLink link: TerminalLink) {
        guard let url = URL(string: link.target) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
#endif
