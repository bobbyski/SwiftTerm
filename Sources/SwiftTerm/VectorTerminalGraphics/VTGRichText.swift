import Foundation

// Rich text for VTG: named styles, single-run styled text, attributed text,
// and attributed text wrapped inside a rectangle.
//
// These are ordinary retained primitives. They carry an id, live in a layer,
// and are usable in the base scene and in VTG Page Mode pages alike. The
// original `text` primitive is untouched.

/// Underline appearance for rich text runs.
public enum VTGTextUnderline: String, Equatable {
    case none
    case single
    case double
    case curly
    case dotted
    case dashed
}

/// Horizontal alignment of rich text lines.
public enum VTGTextAlignment: String, Equatable {
    case left
    case center
    case right
    case justify
}

/// Vertical placement of laid-out text inside a `textBox`.
public enum VTGTextVerticalAlignment: String, Equatable {
    case top
    case middle
    case bottom
}

/// What `y` means for `styledText` and `attrText`.
///
/// `top` matches the historical `text` primitive, whose `y` is the top of the
/// line, so the two can be mixed without offsets.
public enum VTGTextBaseline: String, Equatable {
    case top
    case alphabetic
    case middle
    case bottom
}

/// How lines break when they reach the available width.
public enum VTGTextWrap: String, Equatable {
    case word
    case char
    case none
}

/// What a `textBox` does with lines that do not fit its height.
public enum VTGTextOverflow: String, Equatable {
    case clip
    case grow
    case ellipsis
}

/// A set of text attributes. Every field is optional so styles can cascade:
/// a run's style is laid over the command's base style, which is laid over the
/// defaults.
public struct VTGTextStyle: Equatable {
    public var font: String?
    public var size: Double?
    /// CSS-style weight, 100 through 900.
    public var weight: Int?
    public var italic: Bool?
    public var color: VTGColor?
    /// Run background. A fully transparent color means an explicit `none`.
    public var background: VTGColor?
    public var tracking: Double?
    public var lineHeight: Double?
    public var underline: VTGTextUnderline?
    public var underlineColor: VTGColor?
    public var strike: Bool?

    public init(
        font: String? = nil,
        size: Double? = nil,
        weight: Int? = nil,
        italic: Bool? = nil,
        color: VTGColor? = nil,
        background: VTGColor? = nil,
        tracking: Double? = nil,
        lineHeight: Double? = nil,
        underline: VTGTextUnderline? = nil,
        underlineColor: VTGColor? = nil,
        strike: Bool? = nil
    ) {
        self.font = font
        self.size = size
        self.weight = weight
        self.italic = italic
        self.color = color
        self.background = background
        self.tracking = tracking
        self.lineHeight = lineHeight
        self.underline = underline
        self.underlineColor = underlineColor
        self.strike = strike
    }

    public static let defaultSize = 14.0
    public static let defaultWeight = 400

    /// Return this style with every field `other` sets taking precedence.
    public func overlaid(with other: VTGTextStyle) -> VTGTextStyle {
        VTGTextStyle(
            font: other.font ?? font,
            size: other.size ?? size,
            weight: other.weight ?? weight,
            italic: other.italic ?? italic,
            color: other.color ?? color,
            background: other.background ?? background,
            tracking: other.tracking ?? tracking,
            lineHeight: other.lineHeight ?? lineHeight,
            underline: other.underline ?? underline,
            underlineColor: other.underlineColor ?? underlineColor,
            strike: other.strike ?? strike
        )
    }

    public var resolvedSize: Double { max(1, size ?? Self.defaultSize) }
    public var resolvedWeight: Int { weight ?? Self.defaultWeight }
    public var resolvedColor: VTGColor { color ?? .foreground }
}

/// One run of attributed text: a string and the fully cascaded style it is
/// drawn with, or a line break.
public struct VTGTextRun: Equatable {
    public var text: String
    public var style: VTGTextStyle
    public var isLineBreak: Bool

    public init(text: String, style: VTGTextStyle, isLineBreak: Bool = false) {
        self.text = text
        self.style = style
        self.isLineBreak = isLineBreak
    }

    public static func lineBreak(style: VTGTextStyle) -> VTGTextRun {
        VTGTextRun(text: "\n", style: style, isLineBreak: true)
    }
}

/// Insets applied inside a `textBox`.
public struct VTGTextInsets: Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public static let zero = VTGTextInsets(top: 0, right: 0, bottom: 0, left: 0)

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

/// A retained rich text object.
public struct VTGRichText: Equatable {
    /// The command that produced the object; also decides what `x`/`y` mean.
    public enum Kind: String, Equatable {
        case styled = "styledText"
        case attributed = "attrText"
        case box = "textBox"
    }

    public var id: String
    public var kind: Kind
    public var x: Double
    public var y: Double
    /// Box width for `textBox`; the wrapping width (`maxWidth`) otherwise.
    public var width: Double?
    /// Box height for `textBox`; `nil` means the box grows to fit.
    public var height: Double?
    public var runs: [VTGTextRun]
    public var alignment: VTGTextAlignment
    public var verticalAlignment: VTGTextVerticalAlignment
    public var baseline: VTGTextBaseline
    public var wrap: VTGTextWrap
    public var overflow: VTGTextOverflow
    public var insets: VTGTextInsets
    /// Rotation in degrees about (`x`, `y`).
    public var angle: Double
    /// Fixed line advance for every line, overriding the fonts' own.
    public var lineHeight: Double?

    public init(
        id: String,
        kind: Kind,
        x: Double,
        y: Double,
        width: Double? = nil,
        height: Double? = nil,
        runs: [VTGTextRun],
        alignment: VTGTextAlignment = .left,
        verticalAlignment: VTGTextVerticalAlignment = .top,
        baseline: VTGTextBaseline = .top,
        wrap: VTGTextWrap = .word,
        overflow: VTGTextOverflow = .clip,
        insets: VTGTextInsets = .zero,
        angle: Double = 0,
        lineHeight: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.runs = runs
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.baseline = baseline
        self.wrap = wrap
        self.overflow = overflow
        self.insets = insets
        self.angle = angle
        self.lineHeight = lineHeight
    }

    /// The text of every run joined, with breaks as newlines.
    public var plainText: String {
        runs.map(\.text).joined()
    }
}

/// Named text styles shared by every scene in a session.
///
/// Styles are session state, not scene content: `clear` and `pageClear` leave
/// them alone, and page layers see the same registry as the base scene. A
/// reference type so all of those scenes can share one.
public final class VTGTextStyleRegistry {
    public static let maximumStyles = 256

    public private(set) var styles: [String: VTGTextStyle] = [:]

    public init() {}

    public func style(named id: String) -> VTGTextStyle? {
        styles[id]
    }

    /// Define or replace a style. Returns `false` when the registry is full.
    @discardableResult
    public func define(_ id: String, style: VTGTextStyle) -> Bool {
        guard styles[id] != nil || styles.count < Self.maximumStyles else {
            return false
        }
        styles[id] = style
        return true
    }

    public func removeAll() {
        styles.removeAll()
    }
}

/// Decodes the length-prefixed run payload used by `attrText`, `textBox`, and
/// `textMeasure?`.
///
///     runs      := run*
///     run       := style-ref ":" byte-length ":" utf8-bytes
///     style-ref := <style-id> | "-" | "NL"
///
/// `byte-length` counts UTF-8 bytes, so run text needs no escaping. `NL` is a
/// line break and must have length 0. Run text may not contain C0 controls.
public enum VTGTextRunParser {
    public struct RawRun: Equatable {
        public var styleRef: String
        public var text: String

        public var isLineBreak: Bool { styleRef == "NL" }
        public var usesBaseStyle: Bool { styleRef == "-" }
    }

    /// Return the decoded runs, or `nil` when the payload is malformed. A
    /// malformed payload yields nothing at all rather than a partial object.
    public static func parse(_ payload: String) -> [RawRun]? {
        let bytes = Array(payload.utf8)
        var runs: [RawRun] = []
        var index = 0
        while index < bytes.count {
            guard let refEnd = bytes[index...].firstIndex(of: UInt8(ascii: ":")) else {
                return nil
            }
            let refBytes = bytes[index..<refEnd]
            guard let styleRef = String(bytes: refBytes, encoding: .utf8),
                  isValidStyleRef(styleRef) else {
                return nil
            }
            let lengthStart = refEnd + 1
            guard let lengthEnd = bytes[lengthStart...].firstIndex(of: UInt8(ascii: ":")),
                  lengthEnd > lengthStart,
                  lengthEnd - lengthStart <= 9,
                  let lengthText = String(bytes: bytes[lengthStart..<lengthEnd], encoding: .utf8),
                  lengthText.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let length = Int(lengthText) else {
                return nil
            }
            let textStart = lengthEnd + 1
            let textEnd = textStart + length
            guard textEnd <= bytes.count else {
                return nil
            }
            let textBytes = bytes[textStart..<textEnd]
            guard !textBytes.contains(where: { $0 < 0x20 || $0 == 0x7F }),
                  let text = String(bytes: textBytes, encoding: .utf8) else {
                return nil
            }
            if styleRef == "NL", length != 0 {
                return nil
            }
            runs.append(RawRun(styleRef: styleRef, text: text))
            index = textEnd
        }
        return runs
    }

    /// Encode runs in the wire form. The inverse of ``parse(_:)``.
    public static func encode(_ runs: [(styleRef: String, text: String)]) -> String {
        runs.map { "\($0.styleRef):\($0.text.utf8.count):\($0.text)" }.joined()
    }

    private static func isValidStyleRef(_ value: String) -> Bool {
        if value == "-" || value == "NL" {
            return true
        }
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
