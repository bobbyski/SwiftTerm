import Foundation

/// A locked screen: an exact pixel resolution and text grid, for a program
/// that is reproducing a particular machine.
///
/// **Off unless a program asks for it.** A terminal's canvas is normally
/// whatever the window happens to be, and its text grid is whatever fits the
/// font — right for a terminal, wrong for a 320×200 screen with 40×25
/// characters. `screenLock` fixes both; `screenUnlock` gives the window back.
///
/// The host then draws that screen at a **whole-number multiple** of its size —
/// 320×200 at ×3 is 960×600 — and centres it in the frame, because anything
/// else resamples: a C64's pixels stop being square, and its glyphs grow fringes
/// where one source pixel lands across two. What is left over around the edges
/// stays background, as the border does on the machine being copied.
///
/// A frame too small for even ×1 is the one case with no clean answer: the
/// screen is then scaled to fit, ``Layout/isExact`` says it is not a whole
/// multiple, and the program can offer a smaller mode.
public struct VTGScreenLock: Equatable, Sendable {
    /// The screen's width in VTG pixels — the canvas every drawing command
    /// then addresses, whatever size the window is.
    public let width: Int
    /// The screen's height in VTG pixels.
    public let height: Int
    /// Text columns across that screen.
    public let columns: Int
    /// Text rows down it.
    public let rows: Int

    public init?(width: Int, height: Int, columns: Int, rows: Int) {
        guard width > 0, height > 0, columns > 0, rows > 0 else {
            return nil
        }
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
    }

    /// The canvas a locked program draws into.
    public var canvas: VTGCanvasSize {
        VTGCanvasSize(width: width, height: height)
    }

    /// One character cell in VTG pixels. Fractional when the grid does not
    /// divide the screen — 40 columns of 320 pixels is 8 exactly, and a grid
    /// that does not come out whole is the program's choice to make.
    public var cellSize: (width: Double, height: Double) {
        (width: Double(width) / Double(columns), height: Double(height) / Double(rows))
    }

    /// Where a locked screen sits inside a frame, and how much it is scaled.
    public struct Layout: Equatable, Sendable {
        /// Whole-number multiple of the locked size — 3 means one screen pixel
        /// is a 3×3 block — or, when even ×1 does not fit, the fraction that does.
        public let scale: Double
        /// The screen's rectangle inside the frame, centred, in the frame's units.
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        /// False when the frame was too small for ×1, so the scale is not a
        /// whole multiple and pixels are resampled.
        public let isExact: Bool

        /// One character cell at this scale, in the frame's units.
        public func cellSize(for lock: VTGScreenLock) -> (width: Double, height: Double) {
            let cell = lock.cellSize
            return (width: cell.width * scale, height: cell.height * scale)
        }
    }

    /// Fit this screen into a frame: the largest whole multiple that fits,
    /// centred, with the remainder left as border.
    ///
    /// Sizes are rounded to whole units so the screen lands on pixel
    /// boundaries; a half-pixel origin is what makes a scaled grid blur.
    public func layout(inWidth frameWidth: Double, frameHeight: Double) -> Layout? {
        guard frameWidth > 0, frameHeight > 0 else {
            return nil
        }
        let fit = min(frameWidth / Double(width), frameHeight / Double(height))
        let isExact = fit >= 1
        let scale = isExact ? fit.rounded(.down) : fit
        let scaledWidth = (Double(width) * scale).rounded(.down)
        let scaledHeight = (Double(height) * scale).rounded(.down)
        return Layout(
            scale: scale,
            x: ((frameWidth - scaledWidth) / 2).rounded(.down),
            y: ((frameHeight - scaledHeight) / 2).rounded(.down),
            width: scaledWidth,
            height: scaledHeight,
            isExact: isExact
        )
    }

    /// The `screen` response: what is locked, and how it is being shown.
    public func responseFields(layout: Layout?) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("locked", "1"),
            ("width", String(width)),
            ("height", String(height)),
            ("cols", String(columns)),
            ("rows", String(rows))
        ]
        if let layout {
            fields += [
                ("scale", VTGScreenLock.number(layout.scale)),
                ("x", VTGScreenLock.number(layout.x)),
                ("y", VTGScreenLock.number(layout.y)),
                ("pixelWidth", VTGScreenLock.number(layout.width)),
                ("pixelHeight", VTGScreenLock.number(layout.height)),
                ("exact", layout.isExact ? "1" : "0")
            ]
        }
        return fields
    }

    /// Whole numbers without a decimal tail, so `scale=3` is not `scale=3.0`.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.4g", value)
    }
}
