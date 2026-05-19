import Foundation

/// Stroke endpoint style for VTG stroked primitives.
public enum VTGLineCap: String, Equatable {
    case butt
    case round
    case square
}

/// Stroke corner style for VTG stroked primitives.
public enum VTGLineJoin: String, Equatable {
    case miter
    case round
    case bevel
}

/// Pixel-space point used by multi-segment VTG draw commands.
public struct VTGPoint: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Bezier curve retained by the VTG scene.
public enum VTGCurve: Equatable {
    case quadratic(start: VTGPoint, control: VTGPoint, end: VTGPoint)
    case cubic(start: VTGPoint, control1: VTGPoint, control2: VTGPoint, end: VTGPoint)
}

/// Constrained SVG-like path commands supported by VTG phase 2.
public enum VTGPathCommand: Equatable {
    case move(to: VTGPoint)
    case line(to: VTGPoint)
    case quadratic(control: VTGPoint, end: VTGPoint)
    case cubic(control1: VTGPoint, control2: VTGPoint, end: VTGPoint)
    case close
}

/// RGBA color normalized for AppKit/SwiftUI drawing.
public struct VTGColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public static let foreground = VTGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
