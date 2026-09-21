// A waitpid status is not an exit code. Keep the conversion at the process
// boundary so every terminal consumer receives the documented value.
#if !os(iOS) && !os(Windows)
/// Converts POSIX wait status into shell-style exit codes.
enum LocalProcessExitStatus {
    /// Normal exits return 0...255; signals return 128 + signal. Stopped
    /// processes have not exited and therefore have no exit code.
    static func decode(_ status: Int32) -> Int32? {
        let signal = status & 0x7f
        if signal == 0 { return (status >> 8) & 0xff }
        if signal == 0x7f { return nil }
        return 128 + signal
    }
}
#endif
