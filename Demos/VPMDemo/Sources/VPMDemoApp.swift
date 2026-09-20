import AppKit
import SwiftTerm

/// A terminal window that runs the VTG Page Mode demo script.
///
/// The window is SwiftTerm's `LocalProcessVectorTerminalView` — the view VGTerm
/// uses — running `vpm-demo.sh` in a real pseudo-terminal, so everything on
/// screen arrives as escape sequences through the ordinary terminal parser.
/// When the script finishes the window drops into an interactive shell, where
/// the script can be run again or page-mode sequences typed by hand.
///
/// `--command <program>` runs that program instead of the bundled script,
/// which is how the `VPMPages` command-line demo is launched into a terminal
/// that has page mode. `--capture <dir>` runs unattended and writes an SVG
/// snapshot of the window every half second, then quits.
@main
final class VPMDemoApp: NSObject, NSApplicationDelegate, LocalProcessVectorTerminalViewDelegate {
    private var window: NSWindow!
    private var terminal: LocalProcessVectorTerminalView!
    private var captureDirectory: URL?
    private var captureTimer: Timer?
    private var captureCount = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = VPMDemoApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--capture"), index + 1 < arguments.count {
            captureDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 692),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VTG Page Mode Demo"
        terminal = LocalProcessVectorTerminalView(frame: window.contentView?.bounds ?? .zero)
        terminal.autoresizingMask = [.width, .height]
        terminal.processDelegate = self
        window.contentView = terminal
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        NSApp.activate(ignoringOtherApps: true)
        installMenu()

        var requested: String?
        if let index = arguments.firstIndex(of: "--command"), index + 1 < arguments.count {
            requested = arguments[index + 1]
        }
        guard let program = requested ?? Bundle.main.path(forResource: "vpm-demo", ofType: "sh") else {
            terminal.feed(text: "vpm-demo.sh is missing from the app bundle.\r\n")
            return
        }
        let quoted = "'" + program.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // The bundled script needs bash; a built program runs as itself, and
        // `--command` may carry arguments, in which case it is a command line
        // rather than a path to quote.
        let invocation: String
        if program.hasSuffix(".sh") {
            invocation = "/bin/bash \(quoted)"
        } else if program.contains(" ") {
            invocation = program
        } else {
            invocation = quoted
        }
        let command: String
        if captureDirectory != nil {
            command = program.hasSuffix(".sh") ? "\(invocation) auto" : invocation
        } else {
            command = """
            \(invocation); \
            printf '\\nRun it again:  %s\\n\\n' \(quoted); \
            exec /bin/zsh -i
            """
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-c", command],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )

        if let captureDirectory {
            try? FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.capture()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func capture() {
        guard let captureDirectory else { return }
        captureCount += 1
        let url = captureDirectory.appendingPathComponent(String(format: "frame-%03d.svg", captureCount))
        terminal.exportSVGSnapshot(to: url)
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Dismiss Page", action: #selector(dismissPage), keyEquivalent: "d")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit VTG Page Mode Demo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }

    /// The host's escape hatch: take a page down without the program's help.
    @objc private func dismissPage() {
        terminal.dismissVectorGraphicsPage()
    }

    // MARK: - LocalProcessVectorTerminalViewDelegate

    func sizeChanged(source: LocalProcessVectorTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessVectorTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func bell(source: TerminalView) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard captureDirectory != nil else { return }
        capture()
        captureTimer?.invalidate()
        NSApp.terminate(nil)
    }
}
