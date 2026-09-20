#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension VTGOverlayView {
    /// Apply a constrained VTG path command list to the current CGContext path.
    func applyPathCommands(_ commands: [VTGPathCommand], in context: CGContext) {
        for command in commands {
            switch command {
            case .move(let point):
                context.move(to: CGPoint(x: point.x, y: point.y))
            case .line(let point):
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            case .quadratic(let control, let end):
                context.addQuadCurve(to: CGPoint(x: end.x, y: end.y), control: CGPoint(x: control.x, y: control.y))
            case .cubic(let control1, let control2, let end):
                context.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y)
                )
            case .close:
                context.closePath()
            }
        }
    }

}

extension VTGLineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt:
            return .butt
        case .round:
            return .round
        case .square:
            return .square
        }
    }
}

extension VTGLineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter:
            return .miter
        case .round:
            return .round
        case .bevel:
            return .bevel
        }
    }
}

#endif
