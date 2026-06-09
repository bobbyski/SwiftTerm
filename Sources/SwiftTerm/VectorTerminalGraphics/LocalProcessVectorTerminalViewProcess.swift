#if os(macOS)
import AppKit
import Foundation

extension LocalProcessVectorTerminalView {
    /// Launch a child process inside a pseudo-terminal.
    public func startProcess(
        executable: String = "/bin/bash",
        args: [String] = [],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil
    ) {
        process.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
    }

    /// Terminate the child process.
    public func terminate() {
        process.terminate()
    }

    /// Enable or disable host IO logging for the child process.
    public func setHostLogging(directory: String?) {
        process.setHostLogging(directory: directory)
    }
}
#endif
