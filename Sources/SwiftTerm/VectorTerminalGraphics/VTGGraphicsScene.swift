import Foundation

/// Defines the VTG compositing layer contract shared by the parser, scene, and
/// host response encoder.
///
/// Layer 0 is reserved for the future text/graphics plane where VTG primitives
/// can mingle with terminal cells. Layers 1 through 4 are overlay layers that
/// render above the terminal and may scroll independently for parallax-style
/// effects.
public enum VTGLayerModel {
    /// Shared text/graphics plane reserved for Phase 10 renderer integration.
    public static let textPlaneLayer = 0

    /// First overlay layer. This is the default for current VTG drawing.
    public static let firstOverlayLayer = 1

    /// Last supported overlay layer. Keep this intentionally small.
    public static let lastOverlayLayer = 4

    /// Default layer for commands that omit `layer=`.
    public static let defaultDrawingLayer = firstOverlayLayer

    /// All supported layer numbers.
    public static let supportedRange = textPlaneLayer...lastOverlayLayer

    /// Layers that can be independently scrolled in the current overlay model.
    public static let scrollableRange = firstOverlayLayer...lastOverlayLayer

    /// Human-readable range advertised through `VTG;capabilities?`.
    public static let advertisedRange = "\(textPlaneLayer)-\(lastOverlayLayer)"

    /// Clamp an arbitrary wire value into the supported VTG layer range.
    public static func clamped(_ value: Int) -> Int {
        min(supportedRange.upperBound, max(supportedRange.lowerBound, value))
    }

    /// Return whether the layer may currently receive an overlay scroll offset.
    public static func isScrollable(_ layer: Int) -> Bool {
        scrollableRange.contains(layer)
    }
}

/// A retained drawing primitive in the VectorTerminal overlay scene.
///
/// Each primitive has an ID so apps can redraw by replacing existing shapes
/// instead of clearing and repainting the entire canvas every frame.
public enum VTGPrimitive: Equatable {
    case pixel(id: String, x: Double, y: Double, color: VTGColor)
    case line(id: String, x1: Double, y1: Double, x2: Double, y2: Double, stroke: VTGColor, width: Double)
    case draw(id: String, points: [VTGPoint], stroke: VTGColor, width: Double)
    case curve(id: String, curve: VTGCurve, stroke: VTGColor, width: Double)
    case triangle(id: String, p1: VTGPoint, p2: VTGPoint, p3: VTGPoint, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case path(id: String, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case rect(id: String, x: Double, y: Double, width: Double, height: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case circle(id: String, cx: Double, cy: Double, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case ellipse(id: String, cx: Double, cy: Double, rx: Double, ry: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case text(id: String, x: Double, y: Double, value: String, color: VTGColor, size: Double)
    case image(id: String, x: Double, y: Double, width: Double, height: Double, format: String, data: Data, base64: String)
    case sprite(id: String, assetID: String, x: Double, y: Double, rotation: Double, scale: Double)

    public var id: String {
        switch self {
        case .pixel(let id, _, _, _),
             .line(let id, _, _, _, _, _, _),
             .draw(let id, _, _, _),
             .curve(let id, _, _, _),
             .triangle(let id, _, _, _, _, _, _),
             .path(let id, _, _, _, _),
             .rect(let id, _, _, _, _, _, _, _),
             .circle(let id, _, _, _, _, _, _),
             .ellipse(let id, _, _, _, _, _, _, _),
             .text(let id, _, _, _, _, _),
             .image(let id, _, _, _, _, _, _, _),
             .sprite(let id, _, _, _, _, _):
            return id
        }
    }
}

/// Uploaded bitmap payload that sprite instances can reference cheaply.
public struct VTGSpriteAsset: Equatable {
    public var id: String
    public var format: String
    public var width: Double
    public var height: Double
    public var data: Data
    public var base64: String

    public init(id: String, format: String, width: Double, height: Double, data: Data, base64: String) {
        self.id = id
        self.format = format
        self.width = width
        self.height = height
        self.data = data
        self.base64 = base64
    }
}

/// Uploaded vector payload that sprite instances can reference cheaply.
///
/// The first pass supports one constrained VTG path per asset. That keeps
/// transforms limited to tracked sprite resources while giving small games and
/// demos lightweight vector ships, cursors, and icons.
public struct VTGVectorSpriteAsset: Equatable {
    public var id: String
    public var width: Double
    public var height: Double
    public var commands: [VTGPathCommand]
    public var stroke: VTGColor?
    public var fill: VTGColor?
    public var lineWidth: Double
    public var payload: String

    public init(id: String, width: Double, height: Double, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, payload: String) {
        self.id = id
        self.width = width
        self.height = height
        self.commands = commands
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.payload = payload
    }
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

/// Pixel-space scroll offset for a VTG graphics layer.
public struct VTGLayerOffset: Equatable {
    public var x: Double
    public var y: Double

    public static let zero = VTGLayerOffset(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Rectangular clip bounds for a VTG graphics layer.
public struct VTGLayerClip: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Rectangular interactive region registered by a child app.
public struct VTGHitRegion: Equatable {
    public var id: String
    public var target: String?
    public var layer: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var order: Int

    public init(id: String, target: String?, layer: Int, x: Double, y: Double, width: Double, height: Double, order: Int) {
        self.id = id
        self.target = target
        self.layer = layer
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.order = order
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

/// Retained scene model for VTG overlay primitives.
///
/// The terminal stream remains ANSI-compatible text. VTG commands update this
/// side scene, and `VTGOverlayView` renders it on top of the terminal surface.
public final class VTGGraphicsScene {
    public static let supportedLayerRange = VTGLayerModel.supportedRange

    public private(set) var primitives: [VTGPrimitive] = []
    public private(set) var spriteAssets: [String: VTGSpriteAsset] = [:]
    public private(set) var vectorSpriteAssets: [String: VTGVectorSpriteAsset] = [:]
    public private(set) var defaultLayer = VTGLayerModel.defaultDrawingLayer
    public private(set) var layersByID: [String: Int] = [:]
    public private(set) var layerOffsets: [Int: VTGLayerOffset] = [:]
    public private(set) var layerClips: [Int: VTGLayerClip] = [:]
    public private(set) var layerAlphas: [Int: Double] = [:]
    public private(set) var hitRegions: [String: VTGHitRegion] = [:]
    private var indexesByID: [String: Int] = [:]
    private var nextHitOrder = 0
    private let spriteAssetLimit = 256

    /// Primitives ordered by their current compositing layer.
    ///
    /// Layer 0 is reserved for the future shared text/graphics plane. Until VTG
    /// moves into SwiftTerm, all layers still render in the overlay view; this
    /// ordering gives apps deterministic z-order without claiming layer 0 is
    /// fully mingled with terminal text yet.
    public init() {}

    public var renderPrimitives: [VTGPrimitive] {
        primitives.enumerated()
            .sorted { lhs, rhs in
                let leftLayer = layer(for: lhs.element)
                let rightLayer = layer(for: rhs.element)
                if leftLayer == rightLayer {
                    return lhs.offset < rhs.offset
                }
                return leftLayer < rightLayer
            }
            .map(\.element)
    }

    /// Return the retained layer for a primitive.
    public func layer(for primitive: VTGPrimitive) -> Int {
        layersByID[primitive.id] ?? defaultLayer
    }

    /// Return the current scroll offset for a layer.
    public func offset(for layer: Int) -> VTGLayerOffset {
        layerOffsets[layer] ?? .zero
    }

    /// Return the current clip rectangle for a layer, if one is active.
    public func clip(for layer: Int) -> VTGLayerClip? {
        layerClips[layer]
    }

    /// Return the current opacity multiplier for a layer.
    public func alpha(for layer: Int) -> Double {
        layerAlphas[layer] ?? 1
    }

    /// Return the topmost registered hit region at a pixel coordinate.
    public func hitRegion(at point: VTGPoint) -> VTGHitRegion? {
        hitRegions.values
            .filter { region in
                let offset = offset(for: region.layer)
                let screenX = region.x + offset.x
                let screenY = region.y + offset.y
                guard point.x >= screenX,
                      point.x <= screenX + region.width,
                      point.y >= screenY,
                      point.y <= screenY + region.height else {
                    return false
                }
                if let clip = clip(for: region.layer) {
                    return point.x >= clip.x &&
                        point.x <= clip.x + clip.width &&
                        point.y >= clip.y &&
                        point.y <= clip.y + clip.height
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.layer == rhs.layer {
                    return lhs.order > rhs.order
                }
                return lhs.layer > rhs.layer
            }
            .first
    }

    /// Apply one parsed VTG command to the retained primitive list.
    public func apply(_ command: VectorTerminalGraphicsCommand) {
        switch command.name {
        case "begin", "present", "capabilities?":
            break
        case "defaultLayer":
            defaultLayer = command.layerValue(default: defaultLayer)
        case "layer":
            setPrimitiveLayer(command)
        case "layerScroll":
            setLayerScroll(command)
        case "layerAlpha":
            setLayerAlpha(command)
        case "clip":
            setLayerClip(command)
        case "clipClear":
            clearLayerClip(command)
        case "hit":
            upsertHitRegion(command)
        case "hitClear":
            clearHitRegion(command)
        case "clear":
            primitives.removeAll()
            spriteAssets.removeAll()
            vectorSpriteAssets.removeAll()
            indexesByID.removeAll()
            layersByID.removeAll()
            layerOffsets.removeAll()
            layerClips.removeAll()
            layerAlphas.removeAll()
            hitRegions.removeAll()
            defaultLayer = VTGLayerModel.defaultDrawingLayer
        case "delete":
            if let id = command.parameters["id"] {
                remove(id: id)
            }
        case "pixel":
            upsert(parsePixel(command), command: command)
        case "line":
            upsert(parseLine(command), command: command)
        case "draw":
            upsert(parseDraw(command), command: command)
        case "curve":
            upsert(parseCurve(command), command: command)
        case "triangle":
            upsert(parseTriangle(command), command: command)
        case "path":
            upsert(parsePath(command), command: command)
        case "rect":
            upsert(parseRect(command), command: command)
        case "circle":
            upsert(parseCircle(command), command: command)
        case "ellipse":
            upsert(parseEllipse(command), command: command)
        case "text":
            upsert(parseText(command), command: command)
        case "image":
            upsert(parseImage(command), command: command)
        case "spriteUpload":
            uploadSprite(command)
        case "vectorSpriteUpload":
            uploadVectorSprite(command)
        case "sprite":
            upsert(parseSprite(command), command: command)
        case "spriteMove":
            transformSprite(command, updates: [.position])
        case "spriteRotate":
            transformSprite(command, updates: [.rotation])
        case "spriteTransform":
            transformSprite(command, updates: [.position, .rotation, .scale])
        case "spriteRemove":
            if let id = command.parameters["id"] {
                removeSpriteAsset(id: id)
            }
        case "spriteClear":
            removeAllSpriteAssets()
        default:
            break
        }
    }

    private func upsert(_ primitive: VTGPrimitive?, command: VectorTerminalGraphicsCommand) {
        guard let primitive else {
            return
        }
        layersByID[primitive.id] = command.layerValue(default: layersByID[primitive.id] ?? defaultLayer)
        if let index = indexesByID[primitive.id] {
            primitives[index] = primitive
        } else {
            indexesByID[primitive.id] = primitives.count
            primitives.append(primitive)
        }
    }

    private func remove(id: String) {
        guard let index = indexesByID[id] else {
            return
        }
        primitives.remove(at: index)
        layersByID.removeValue(forKey: id)
        // Removing from an array shifts later indexes, so rebuild the small
        // lookup table rather than trying to patch every affected index.
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func setPrimitiveLayer(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              indexesByID[id] != nil else {
            return
        }
        layersByID[id] = command.layerValue(default: layersByID[id] ?? defaultLayer)
    }

    /// Return an uploaded sprite asset for renderers/exporters.
    public func spriteAsset(id: String) -> VTGSpriteAsset? {
        spriteAssets[id]
    }

    /// Return an uploaded vector sprite asset for renderers/exporters.
    public func vectorSpriteAsset(id: String) -> VTGVectorSpriteAsset? {
        vectorSpriteAssets[id]
    }

    private func parsePixel(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .pixel(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            color: command.color("color") ?? command.color("fill") ?? .foreground
        )
    }

    private func parseLine(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .line(
            id: id,
            x1: command.double("x1"),
            y1: command.double("y1"),
            x2: command.double("x2"),
            y2: command.double("y2"),
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1))
        )
    }

    private func parseDraw(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        // `draw` carries its arbitrary point list in the APC payload:
        // `x,y x,y x,y`. Keeping the large list out of comma parameters makes
        // the command easier to stream and easier for non-Swift clients to emit.
        let points = (command.payload ?? "")
            .split(separator: " ", omittingEmptySubsequences: true)
            .compactMap { pair -> VTGPoint? in
                let coordinates = pair.split(separator: ",", maxSplits: 1)
                guard coordinates.count == 2,
                      let x = Double(coordinates[0]),
                      let y = Double(coordinates[1]) else {
                    return nil
                }
                return VTGPoint(x: x, y: y)
            }
        guard points.count >= 2 else {
            return nil
        }
        return .draw(
            id: id,
            points: points,
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1))
        )
    }

    private func parseCurve(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        let start = VTGPoint(x: command.double("x1"), y: command.double("y1"))
        let end = VTGPoint(x: command.double("x2"), y: command.double("y2"))
        let curve: VTGCurve
        switch command.parameters["kind"] {
        case "cubic":
            curve = .cubic(
                start: start,
                control1: VTGPoint(x: command.double("c1x"), y: command.double("c1y")),
                control2: VTGPoint(x: command.double("c2x"), y: command.double("c2y")),
                end: end
            )
        default:
            curve = .quadratic(
                start: start,
                control: VTGPoint(x: command.double("cx"), y: command.double("cy")),
                end: end
            )
        }
        return .curve(
            id: id,
            curve: curve,
            stroke: command.color("stroke") ?? .foreground,
            width: max(1, command.double("width", default: 1))
        )
    }

    private func parseTriangle(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .triangle(
            id: id,
            p1: VTGPoint(x: command.double("x1"), y: command.double("y1")),
            p2: VTGPoint(x: command.double("x2"), y: command.double("y2")),
            p3: VTGPoint(x: command.double("x3"), y: command.double("y3")),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    private func parsePath(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              let commands = VTGPathParser.parse(command.payload ?? ""),
              commands.isEmpty == false else {
            return nil
        }
        return .path(
            id: id,
            commands: commands,
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    private func parseRect(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .rect(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            width: command.double("w"),
            height: command.double("h"),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    private func parseCircle(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .circle(
            id: id,
            cx: command.double("cx"),
            cy: command.double("cy"),
            radius: command.double("r"),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    private func parseEllipse(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .ellipse(
            id: id,
            cx: command.double("cx"),
            cy: command.double("cy"),
            rx: command.double("rx"),
            ry: command.double("ry"),
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("width", default: 1))
        )
    }

    private func parseText(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"] else {
            return nil
        }
        return .text(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            value: command.payload ?? "",
            color: command.color("color") ?? .foreground,
            size: max(1, command.double("size", default: 14))
        )
    }

    private func parseImage(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              let payload = command.payload,
              let data = Data(base64Encoded: payload) else {
            return nil
        }
        let format = command.parameters["format"] ?? "png"
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return nil
        }
        return .image(
            id: id,
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height,
            format: format,
            data: data,
            base64: payload
        )
    }

    private func uploadSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              spriteAssets[id] != nil || vectorSpriteAssets[id] != nil || (spriteAssets.count + vectorSpriteAssets.count) < spriteAssetLimit,
              let payload = command.payload,
              let data = Data(base64Encoded: payload) else {
            return
        }
        let format = (command.parameters["format"] ?? "png").lowercased()
        guard format == "png" || format == "jpeg" || format == "jpg" else {
            return
        }
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return
        }
        vectorSpriteAssets.removeValue(forKey: id)
        spriteAssets[id] = VTGSpriteAsset(
            id: id,
            format: format == "jpg" ? "jpeg" : format,
            width: width,
            height: height,
            data: data,
            base64: payload
        )
    }

    private func uploadVectorSprite(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              vectorSpriteAssets[id] != nil || spriteAssets[id] != nil || (spriteAssets.count + vectorSpriteAssets.count) < spriteAssetLimit,
              let payload = command.payload,
              let commands = VTGPathParser.parse(payload),
              commands.isEmpty == false else {
            return
        }
        let width = command.double("width", default: command.double("w"))
        let height = command.double("height", default: command.double("h"))
        guard width > 0, height > 0 else {
            return
        }
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets[id] = VTGVectorSpriteAsset(
            id: id,
            width: width,
            height: height,
            commands: commands,
            stroke: command.color("stroke"),
            fill: command.color("fill"),
            lineWidth: max(1, command.double("lineWidth", default: command.double("width", default: 1))),
            payload: payload
        )
    }

    private func parseSprite(_ command: VectorTerminalGraphicsCommand) -> VTGPrimitive? {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id),
              let assetID = command.parameters["image"] ?? command.parameters["asset"],
              spriteAssets[assetID] != nil || vectorSpriteAssets[assetID] != nil else {
            return nil
        }
        return .sprite(
            id: id,
            assetID: assetID,
            x: command.double("x"),
            y: command.double("y"),
            rotation: command.double("rotation"),
            scale: max(0.01, command.double("scale", default: 1))
        )
    }

    private struct SpriteUpdateOptions: OptionSet {
        let rawValue: Int

        static let position = SpriteUpdateOptions(rawValue: 1 << 0)
        static let rotation = SpriteUpdateOptions(rawValue: 1 << 1)
        static let scale = SpriteUpdateOptions(rawValue: 1 << 2)
    }

    private func transformSprite(_ command: VectorTerminalGraphicsCommand, updates: SpriteUpdateOptions) {
        guard let id = command.parameters["id"],
              let index = indexesByID[id],
              case .sprite(let spriteID, let assetID, let currentX, let currentY, let currentRotation, let currentScale) = primitives[index] else {
            return
        }
        let x = updates.contains(.position) ? command.double("x", default: currentX) : currentX
        let y = updates.contains(.position) ? command.double("y", default: currentY) : currentY
        let rotation = updates.contains(.rotation) ? command.double("rotation", default: currentRotation) : currentRotation
        let scale = updates.contains(.scale) ? max(0.01, command.double("scale", default: currentScale)) : currentScale
        primitives[index] = .sprite(id: spriteID, assetID: assetID, x: x, y: y, rotation: rotation, scale: scale)
    }

    private func removeSpriteAsset(id: String) {
        spriteAssets.removeValue(forKey: id)
        vectorSpriteAssets.removeValue(forKey: id)
        var removedPrimitiveIDs: [String] = []
        primitives.removeAll { primitive in
            if case .sprite(_, let assetID, _, _, _, _) = primitive {
                let shouldRemove = assetID == id
                if shouldRemove {
                    removedPrimitiveIDs.append(primitive.id)
                }
                return shouldRemove
            }
            return false
        }
        for primitiveID in removedPrimitiveIDs {
            layersByID.removeValue(forKey: primitiveID)
        }
        rebuildIndexes()
    }

    private func removeAllSpriteAssets() {
        spriteAssets.removeAll()
        vectorSpriteAssets.removeAll()
        var removedPrimitiveIDs: [String] = []
        primitives.removeAll { primitive in
            if case .sprite = primitive {
                removedPrimitiveIDs.append(primitive.id)
                return true
            }
            return false
        }
        for primitiveID in removedPrimitiveIDs {
            layersByID.removeValue(forKey: primitiveID)
        }
        rebuildIndexes()
    }

    private func setLayerScroll(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer) else {
            return
        }
        layerOffsets[layer] = VTGLayerOffset(
            x: command.double("x", default: offset(for: layer).x),
            y: command.double("y", default: offset(for: layer).y)
        )
    }

    private func setLayerAlpha(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard VTGLayerModel.isScrollable(layer) else {
            return
        }
        let alpha = min(1, max(0, command.double("alpha", default: 1)))
        if alpha >= 0.999 {
            layerAlphas.removeValue(forKey: layer)
        } else {
            layerAlphas[layer] = alpha
        }
    }

    private func setLayerClip(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        guard layer >= 0 else {
            return
        }
        let width = command.double("w", default: command.double("width"))
        let height = command.double("h", default: command.double("height"))
        guard width > 0, height > 0 else {
            return
        }
        layerClips[layer] = VTGLayerClip(
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height
        )
    }

    private func clearLayerClip(_ command: VectorTerminalGraphicsCommand) {
        let layer = command.layerValue(default: defaultLayer)
        layerClips.removeValue(forKey: layer)
    }

    private func upsertHitRegion(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              Self.isValidIdentifier(id) else {
            return
        }
        let width = command.double("w", default: command.double("width"))
        let height = command.double("h", default: command.double("height"))
        guard width > 0, height > 0 else {
            return
        }
        let order = hitRegions[id]?.order ?? nextHitOrder
        if hitRegions[id] == nil {
            nextHitOrder += 1
        }
        let rawTarget = command.parameters["target"]
        let target = rawTarget.flatMap { Self.isValidIdentifier($0) ? $0 : nil }
        hitRegions[id] = VTGHitRegion(
            id: id,
            target: target,
            layer: command.layerValue(default: defaultLayer),
            x: command.double("x"),
            y: command.double("y"),
            width: width,
            height: height,
            order: order
        )
    }

    private func clearHitRegion(_ command: VectorTerminalGraphicsCommand) {
        if let id = command.parameters["id"] {
            hitRegions.removeValue(forKey: id)
        } else if let layerValue = command.parameters["layer"].flatMap(Int.init) {
            hitRegions = hitRegions.filter { $0.value.layer != layerValue }
        } else {
            hitRegions.removeAll()
        }
    }

    private func rebuildIndexes() {
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard value.isEmpty == false, value.count <= 64 else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
    }
}

/// Tiny parser for the constrained VTG path grammar.
///
/// Supported commands intentionally mirror the common SVG command names but only
/// absolute coordinates are accepted in this first pass: `M`, `L`, `Q`, `C`,
/// and `Z`.
private enum VTGPathParser {
    static func parse(_ payload: String) -> [VTGPathCommand]? {
        let tokens = tokenize(payload)
        guard tokens.isEmpty == false else {
            return nil
        }
        var index = 0
        var commands: [VTGPathCommand] = []

        func nextNumber() -> Double? {
            guard index < tokens.count, let value = Double(tokens[index]) else {
                return nil
            }
            index += 1
            return value
        }

        func nextPoint() -> VTGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else {
                return nil
            }
            return VTGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let token = tokens[index].uppercased()
            index += 1
            switch token {
            case "M":
                guard let point = nextPoint() else { return nil }
                commands.append(.move(to: point))
            case "L":
                guard let point = nextPoint() else { return nil }
                commands.append(.line(to: point))
            case "Q":
                guard let control = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.quadratic(control: control, end: end))
            case "C":
                guard let control1 = nextPoint(), let control2 = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.cubic(control1: control1, control2: control2, end: end))
            case "Z":
                commands.append(.close)
            default:
                return nil
            }
        }
        return commands
    }

    private static func tokenize(_ payload: String) -> [String] {
        var expanded = ""
        for character in payload {
            if "MLQCZmlqcz".contains(character) {
                expanded.append(" ")
                expanded.append(character)
                expanded.append(" ")
            } else if character == "," || character.isWhitespace {
                expanded.append(" ")
            } else {
                expanded.append(character)
            }
        }
        return expanded.split(separator: " ").map(String.init)
    }
}

private extension VectorTerminalGraphicsCommand {
    /// Read a numeric command parameter, returning a harmless default when the
    /// child application sends malformed input.
    func double(_ key: String, default defaultValue: Double = 0) -> Double {
        guard let raw = parameters[key], let value = Double(raw) else {
            return defaultValue
        }
        return value
    }

    /// Parse an optional color parameter where `"none"` means transparent.
    func color(_ key: String) -> VTGColor? {
        guard let raw = parameters[key], raw != "none" else {
            return nil
        }
        return VTGColor(hex: raw)
    }

    /// Read and clamp a VTG layer parameter.
    func layerValue(default defaultValue: Int) -> Int {
        let raw = parameters["layer"] ?? parameters["value"]
        guard let raw, let value = Int(raw) else {
            return defaultValue
        }
        return VTGLayerModel.clamped(value)
    }
}

extension VTGColor {
    /// Initialize from `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6 || raw.count == 8, let value = UInt64(raw, radix: 16) else {
            return nil
        }
        if raw.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xff) / 255,
                green: Double((value >> 16) & 0xff) / 255,
                blue: Double((value >> 8) & 0xff) / 255,
                alpha: Double(value & 0xff) / 255
            )
        }
    }
}
