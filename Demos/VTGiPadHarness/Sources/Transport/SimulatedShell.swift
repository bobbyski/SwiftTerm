import Foundation

/// A shell that is not a shell: a command loop over programs that live in the
/// app, for a platform where there is no process to run.
///
/// It exists for two reasons. A freshly installed iPad app should do something
/// useful with no network at all, and BASICStudio's interpreter needs a place
/// to be typed at when it arrives — `register(_:as:)` is that place.
///
/// It emits OSC 133 prompt marks on purpose, so VTG Page Mode's prompt-mark
/// teardown behaves identically here and over SSH. A page left open by a
/// program that ended comes down when the next prompt appears, locally too.
final class SimulatedShell: EmbeddedProgram {
    private var out: ((String) -> Void)?
    private var line = ""
    private var cols = 80
    private var rows = 24
    /// Set while a command is running; a long command checks it.
    private var isInterrupted = false
    /// A program that has the terminal until it says it is done.
    ///
    /// This is what a real program is: while it holds the foreground the shell
    /// prints no prompt, so a page it opened stays up. BASICStudio's
    /// interpreter is this shape.
    private var foreground: ((ArraySlice<UInt8>) -> Bool)?
    /// True while an escape sequence is arriving, so replies from the terminal
    /// are not echoed back as if they had been typed.
    private var inEscape = false
    private var commands: [String: (ArraySlice<String>) -> Void] = [:]

    // MARK: - EmbeddedProgram

    func start(cols: Int, rows: Int, out: @escaping (String) -> Void) {
        self.out = out
        self.cols = cols
        self.rows = rows
        installBuiltins()
        write("\u{1b}[1mSwiftTerm on iPad\u{1b}[0m — a simulated shell, with no process behind it.\r\n")
        write("Type \u{1b}[36mhelp\u{1b}[0m. Nothing here talks to the network.\r\n\r\n")
        prompt()
    }

    func receive(_ bytes: ArraySlice<UInt8>) {
        // A VTG reply is an answer to a question this program asked, not
        // something the user typed. Swallow the whole sequence.
        var typed: [UInt8] = []
        for byte in bytes {
            if inEscape {
                if byte == 0x5c || byte == 0x07 {      // ST or BEL ends it
                    inEscape = false
                }
                continue
            }
            if byte == 0x1b {
                inEscape = true
                continue
            }
            typed.append(byte)
        }
        guard !typed.isEmpty else {
            return
        }
        if let foreground {
            if foreground(typed[...]) {
                self.foreground = nil
                prompt()
            }
            return
        }
        for byte in typed {
            switch byte {
            case 0x0d, 0x0a:                     // Return
                write("\r\n")
                let entered = line
                line = ""
                run(entered)
                // A command that took the foreground gets no prompt: the
                // prompt mark would end the page it just opened.
                if foreground == nil {
                    prompt()
                }
            case 0x7f, 0x08:                     // Backspace
                if !line.isEmpty {
                    line.removeLast()
                    write("\u{8} \u{8}")
                }
            case 0x03:                           // Ctrl-C
                write("^C\r\n")
                line = ""
                interrupt()
                prompt()
            case 0x15:                           // Ctrl-U
                write(String(repeating: "\u{8} \u{8}", count: line.count))
                line = ""
            case 0x20...0x7e:
                let character = Character(UnicodeScalar(byte))
                line.append(character)
                write(String(character))         // Local echo: no far end to do it.
            default:
                break
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }

    /// Cooperative: this sets a flag, and a command that wants to be
    /// interruptible looks at it. A command that never looks is a command the
    /// user cannot stop, which is worth knowing when you write one.
    func interrupt() {
        isInterrupted = true
    }

    func stop() {
        out = nil
    }

    // MARK: - Extending it

    /// Add a program to the shell. This is how BASICStudio's interpreter, or
    /// anything else that reads and writes a terminal, joins in.
    func register(_ command: @escaping (ArraySlice<String>) -> Void, as name: String) {
        commands[name] = command
    }

    // MARK: - The loop

    private func write(_ text: String) {
        out?(text)
    }

    /// OSC 133;A is the prompt mark. Emitting it is what lets the terminal
    /// know a program has finished — the one teardown signal that also works
    /// over SSH.
    private func prompt() {
        write("\u{1b}]133;A\u{7}\u{1b}[36mipad\u{1b}[0m $ ")
    }

    private func run(_ input: String) {
        isInterrupted = false
        let words = input.split(separator: " ").map(String.init)
        guard let name = words.first else {
            return
        }
        guard let command = commands[name] else {
            write("\u{1b}[31m\(name): not found\u{1b}[0m — try \u{1b}[36mhelp\u{1b}[0m\r\n")
            return
        }
        command(words[1...])
    }

    private func installBuiltins() {
        register({ [weak self] _ in
            guard let self else { return }
            let names = self.commands.keys.sorted().joined(separator: "  ")
            self.write("""
                This shell runs programs that live inside the app. There is no
                /usr/bin to list and no process to start: iOS does not allow
                one, so a session is a connection — and this one loops back
                into the app itself.\r\n\r\n
                """.replacingOccurrences(of: "\n", with: "\r\n"))
            self.write("  \(names)\r\n")
        }, as: "help")

        register({ [weak self] _ in
            self?.write("\u{1b}[2J\u{1b}[H")
        }, as: "clear")

        register({ [weak self] arguments in
            self?.write(arguments.joined(separator: " ") + "\r\n")
        }, as: "echo")

        register({ [weak self] _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm:ss"
            self?.write(formatter.string(from: Date()) + "\r\n")
        }, as: "date")

        register({ [weak self] _ in
            guard let self else { return }
            self.write("terminal \(self.cols)x\(self.rows), no process, no pty\r\n")
        }, as: "size")

        register({ [weak self] _ in
            guard let self else { return }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let contents = documents.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }
            guard let contents, !contents.isEmpty else {
                self.write("The app's documents folder is empty. It is the only folder there is.\r\n")
                return
            }
            self.write(contents.sorted().joined(separator: "\r\n") + "\r\n")
        }, as: "files")

        register({ [weak self] _ in
            self?.write(HarnessScenes.graphicsBody)
        }, as: "draw")

        register({ [weak self] _ in
            guard let self else { return }
            self.write("Showing a page. It stays up while this program runs — press any key.\r\n")
            self.write(HarnessScenes.pageBody)
            // Hold the foreground, so no prompt is printed. That matters: the
            // shell's prompt mark is what ends page mode, so a page and a
            // prompt cannot be on screen at the same time by design.
            self.foreground = { [weak self] _ in
                self?.write(HarnessScenes.vtg("pageEnd"))
                self?.write("\r\nPage closed.\r\n")
                return true
            }
        }, as: "page")

        register({ [weak self] _ in
            self?.write(HarnessScenes.vtg("pageEnd") + HarnessScenes.vtg("clear"))
        }, as: "cls")

        register({ [weak self] _ in
            guard let self else { return }
            self.write("A page taller than the screen. Drag it; press any key to close.\r\n")
            self.write(HarnessScenes.scrollableDocument)
            self.foreground = { [weak self] _ in
                self?.write(HarnessScenes.vtg("pageEnd") + "\r\nDocument closed.\r\n")
                return true
            }
        }, as: "doc")
    }
}
