import Foundation

/// Splits a terminal byte stream between the root terminal and VTG windows.
///
/// ```text
///   pty bytes ──▶ VTGWindowRouter ──┬──▶ root terminal      (target nil)
///                                   ├──▶ window "map"       (after windowSelect,id=map)
///                                   └──▶ window commands    (windowCreate, windowRaise, …)
/// ```
///
/// One program, one pty, many windows: `windowSelect,id=<w>` sends everything
/// after it — text and VTG commands alike — to window `w`, until the next
/// select; `id=root` goes back to the terminal itself. The router recognizes
/// only the window commands (`VTGWindowRouter.managedCommands`); every other
/// byte, every other escape sequence and every other VTG command reaches its
/// target untouched, so each window's own emulator parses its own stream.
///
/// **No windows, no cost.** A chunk with no `ESC _ VTG;window` in it, sent
/// while the root is selected, comes back as the caller's own slice — no copy.
/// The scan is one pass looking for ESC.
///
/// A window command split across reads is held until its terminator arrives.
/// Anything that turns out not to be a window command is released at once, so
/// a large sprite upload is never buffered here.
public final class VTGWindowRouter {
    /// One piece of routed output, in stream order.
    public enum Segment: Equatable {
        /// Bytes for a target: nil is the root terminal, otherwise a window id.
        case bytes(ArraySlice<UInt8>, target: String?)
        /// A window command, parsed, for the window manager.
        case command(VectorTerminalGraphicsCommand)
    }

    /// The VTG commands the router takes out of the stream. Everything else
    /// named `window…` — Page Mode's `windowCanvas?` — passes through.
    public static let managedCommands: Set<String> = [
        "windowCreate", "windowClose", "windowSelect", "windowMove", "windowResize",
        "windowRaise", "windowLower", "windowOrder", "windowFocus",
        "windowHide", "windowShow", "windows?", "windowEvents",
    ]

    /// Longest window command held across reads. Window commands are short;
    /// anything longer is released as ordinary bytes rather than buffered.
    static let maximumHeldBytes = 4096

    private static let introducer = Array("\u{1B}_VTG;window".utf8)
    private static let escape: UInt8 = 0x1B
    private static let backslash: UInt8 = 0x5C

    /// Where bytes go until the next `windowSelect`: nil is the root.
    public private(set) var selectedWindow: String?

    /// Bytes of a possible window command carried over from the last read.
    private var held: [UInt8] = []

    private let parser = VectorTerminalGraphicsParser()

    public init() {}

    /// Send everything to the root again and forget any partial command, for
    /// a terminal reset or a program that has gone.
    public func reset() {
        selectedWindow = nil
        held.removeAll()
    }

    /// Whether a read can go straight to the root, untouched: nothing held,
    /// the root selected, and no window command in it. The common case, and
    /// the whole cost of windows for a program that never uses them.
    public func passesStraightThrough(_ bytes: ArraySlice<UInt8>) -> Bool {
        held.isEmpty && selectedWindow == nil && !Self.mayContainIntroducer(bytes)
    }

    /// Route one read.
    public func route(_ bytes: ArraySlice<UInt8>) -> [Segment] {
        if passesStraightThrough(bytes) {
            return bytes.isEmpty ? [] : [.bytes(bytes, target: nil)]
        }
        let input: ArraySlice<UInt8>
        if held.isEmpty {
            input = bytes
        } else {
            input = (held + bytes)[...]
            held.removeAll()
        }
        return split(input)
    }

    /// The window to select after `windowSelect`: nil for root, which is
    /// also what an empty or missing id means.
    public func select(_ id: String?) {
        selectedWindow = (id == nil || id == "root" || id == "") ? nil : id
    }

    // MARK: - Scanning

    /// A quick pre-check: true unless the chunk certainly holds no window
    /// command, nor the start of one at its end.
    ///
    /// This runs on every read. Real output is full of ESC and almost never
    /// holds `ESC _ VTG;window`, so both scans find each ESC fast and reject
    /// almost every one on the byte after it (`ESC [`). Optimized builds scan
    /// sixteen bytes at a time; debug builds, where Swift SIMD is not
    /// optimized and ran 70% slower than the terminal itself, use the C
    /// library's `memchr`, which is fast in every build. Both are tested.
    private static func mayContainIntroducer(_ bytes: ArraySlice<UInt8>) -> Bool {
        #if DEBUG
        return scanWithMemchr(bytes)
        #else
        return scanWithSIMD(bytes)
        #endif
    }

    /// The sixteen-bytes-at-a-time scan, for optimized builds.
    static func scanWithSIMD(_ bytes: ArraySlice<UInt8>) -> Bool {
        bytes.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let count = buffer.count
            let raw = UnsafeRawPointer(base)
            let escapes = SIMD16<UInt8>(repeating: escape)
            var index = 0
            while index + 16 <= count {
                let block = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
                let hits = block .== escapes
                if any(hits) {
                    for lane in 0..<16 where hits[lane] {
                        if startsIntroducer(base, count, at: index + lane) {
                            return true
                        }
                    }
                }
                index += 16
            }
            while index < count {
                if base[index] == escape, startsIntroducer(base, count, at: index) {
                    return true
                }
                index += 1
            }
            return false
        }
    }

    /// The `memchr` scan, for debug builds.
    static func scanWithMemchr(_ bytes: ArraySlice<UInt8>) -> Bool {
        bytes.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let count = buffer.count
            var offset = 0
            while offset < count, let found = memchr(base + offset, Int32(escape), count - offset) {
                let index = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
                if startsIntroducer(base, count, at: index) {
                    return true
                }
                offset = index + 1
            }
            return false
        }
    }

    /// Whether the ESC at `index` begins the introducer, or might: true when
    /// the bytes run out before it can be told apart.
    private static func startsIntroducer(_ base: UnsafePointer<UInt8>, _ count: Int, at index: Int) -> Bool {
        for offset in 1..<introducer.count {
            if index + offset >= count {
                return true
            }
            if base[index + offset] != introducer[offset] {
                return false
            }
        }
        return true
    }

    private enum PrefixMatch {
        case none
        /// The chunk ends inside the introducer.
        case partial
        case full
    }

    private static func prefixMatch(_ bytes: ArraySlice<UInt8>, at start: Int) -> PrefixMatch {
        for (offset, expected) in introducer.enumerated() {
            let index = start + offset
            if index >= bytes.endIndex {
                return .partial
            }
            if bytes[index] != expected {
                return .none
            }
        }
        return .full
    }

    private func split(_ input: ArraySlice<UInt8>) -> [Segment] {
        var segments: [Segment] = []
        var runStart = input.startIndex
        var index = input.startIndex

        func flushRun(upTo end: Int) {
            if end > runStart {
                segments.append(.bytes(input[runStart..<end], target: selectedWindow))
            }
        }

        while let escapeIndex = input[index...].firstIndex(of: Self.escape) {
            switch Self.prefixMatch(input, at: escapeIndex) {
            case .none:
                index = escapeIndex + 1
                continue
            case .partial:
                flushRun(upTo: escapeIndex)
                held = Array(input[escapeIndex...])
                return segments
            case .full:
                break
            }
            // Read the command name, which follows "ESC _ VTG;".
            let nameStart = escapeIndex + 6
            var nameEnd = nameStart
            while nameEnd < input.endIndex, !Self.endsName(input[nameEnd]) {
                nameEnd += 1
            }
            if nameEnd == input.endIndex {
                if input.endIndex - escapeIndex > Self.maximumHeldBytes {
                    index = escapeIndex + 1
                    continue
                }
                flushRun(upTo: escapeIndex)
                held = Array(input[escapeIndex...])
                return segments
            }
            let name = String(decoding: input[nameStart..<nameEnd], as: UTF8.self)
            guard Self.managedCommands.contains(name) else {
                index = escapeIndex + 1
                continue
            }
            // A window command: find its string terminator, ESC \.
            guard let terminator = Self.findTerminator(input, from: nameEnd) else {
                if input.endIndex - escapeIndex > Self.maximumHeldBytes {
                    print("VTGWindowRouter: \(name) longer than \(Self.maximumHeldBytes) bytes; passed through")
                    index = escapeIndex + 1
                    continue
                }
                flushRun(upTo: escapeIndex)
                held = Array(input[escapeIndex...])
                return segments
            }
            flushRun(upTo: escapeIndex)
            let sequenceEnd = terminator + 2
            if let command = parser.feed(input[escapeIndex..<sequenceEnd]).commands.first {
                if command.name == "windowSelect" {
                    select(command.parameters["id"])
                }
                segments.append(.command(command))
            }
            runStart = sequenceEnd
            index = sequenceEnd
        }
        flushRun(upTo: input.endIndex)
        return segments
    }

    private static func endsName(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: ",") || byte == UInt8(ascii: ";") || byte == escape || byte == 0x07
    }

    private static func findTerminator(_ input: ArraySlice<UInt8>, from start: Int) -> Int? {
        var index = start
        while index + 1 < input.endIndex {
            if input[index] == escape, input[index + 1] == backslash {
                return index
            }
            index += 1
        }
        return nil
    }
}
