import TerminalTransports

/// The harness's own programs for the simulated shell.
///
/// The shell lives in the TerminalTransports package and knows nothing about
/// VTG scenes; these are registered from outside, the same way BASICStudio's
/// interpreter will be. `page` and `doc` hold the foreground, because the
/// shell's prompt mark is what ends page mode.
enum HarnessShellCommands {
    static func install(in shell: SimulatedShell) {
        shell.register({ [weak shell] _ in
            shell?.write(HarnessScenes.graphicsBody)
        }, as: "draw")

        shell.register({ [weak shell] _ in
            shell?.write(HarnessScenes.vtg("pageEnd") + HarnessScenes.vtg("clear"))
        }, as: "cls")

        shell.register({ [weak shell] _ in
            guard let shell else { return }
            shell.write("Showing a page. It stays up while this program runs — press any key.\r\n")
            shell.write(HarnessScenes.pageBody)
            shell.takeForeground { [weak shell] _ in
                shell?.write(HarnessScenes.vtg("pageEnd") + "\r\nPage closed.\r\n")
                return true
            }
        }, as: "page")

        shell.register({ [weak shell] _ in
            guard let shell else { return }
            shell.write("A page taller than the screen. Drag it; press any key to close.\r\n")
            shell.write(HarnessScenes.scrollableDocument)
            shell.takeForeground { [weak shell] _ in
                shell?.write(HarnessScenes.vtg("pageEnd") + "\r\nDocument closed.\r\n")
                return true
            }
        }, as: "doc")
    }
}
