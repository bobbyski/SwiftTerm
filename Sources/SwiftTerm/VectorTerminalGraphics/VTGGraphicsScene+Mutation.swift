import Foundation

/// Retained primitive and scene-wide state mutation helpers for ``VTGGraphicsScene``.
extension VTGGraphicsScene {
    func clear() {
        primitives.removeAll()
        spriteAssets.removeAll()
        vectorSpriteAssets.removeAll()
        indexedSpriteAssets.removeAll()
        indexesByID.removeAll()
        layersByID.removeAll()
        layerOffsets.removeAll()
        layerClips.removeAll()
        layerAlphas.removeAll()
        viewportModes.removeAll()
        viewportScales.removeAll()
        hitRegions.removeAll()
        defaultLayer = VTGLayerModel.defaultDrawingLayer
    }

    func upsert(_ primitive: VTGPrimitive?, command: VectorTerminalGraphicsCommand) {
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

    func remove(id: String) {
        guard let index = indexesByID[id] else {
            return
        }
        primitives.remove(at: index)
        layersByID.removeValue(forKey: id)
        // Removing from an array shifts later indexes, so rebuild the small
        // lookup table rather than trying to patch every affected index.
        indexesByID = Dictionary(uniqueKeysWithValues: primitives.enumerated().map { ($0.element.id, $0.offset) })
    }

    func setPrimitiveLayer(_ command: VectorTerminalGraphicsCommand) {
        guard let id = command.parameters["id"],
              indexesByID[id] != nil else {
            return
        }
        layersByID[id] = command.layerValue(default: layersByID[id] ?? defaultLayer)
    }

    func clearRegion(_ command: VectorTerminalGraphicsCommand) {
        guard let region = parseClearRegion(command) else {
            return
        }
        let targetLayer = command.layerValue(default: defaultLayer)
        let removedIDs = primitives.compactMap { primitive -> String? in
            guard layer(for: primitive) == targetLayer,
                  let bounds = bounds(for: primitive),
                  bounds.intersects(region) else {
                return nil
            }
            return primitive.id
        }
        for id in removedIDs {
            remove(id: id)
        }
    }

    private func parseClearRegion(_ command: VectorTerminalGraphicsCommand) -> VTGBounds? {
        let width = command.double("w", default: command.double("width"))
        let height = command.double("h", default: command.double("height"))
        guard width > 0, height > 0 else {
            return nil
        }
        return VTGBounds(
            minX: command.double("x"),
            minY: command.double("y"),
            maxX: command.double("x") + width,
            maxY: command.double("y") + height
        )
    }

    private func bounds(for primitive: VTGPrimitive) -> VTGBounds? {
        switch primitive {
        case .pixel(_, let x, let y, _):
            return VTGBounds(minX: x, minY: y, maxX: x + 1, maxY: y + 1)
        case .clearRect(_, let x, let y, let width, let height):
            return VTGBounds(minX: x, minY: y, maxX: x + width, maxY: y + height)
        case .line(_, let x1, let y1, let x2, let y2, _, let width, _):
            return VTGBounds(points: [VTGPoint(x: x1, y: y1), VTGPoint(x: x2, y: y2)])?.expanded(by: width / 2)
        case .draw(_, let points, _, let width, _, _):
            return VTGBounds(points: points)?.expanded(by: width / 2)
        case .curve(_, let curve, _, let width, _, _):
            return VTGBounds(points: curve.controlBoundsPoints)?.expanded(by: width / 2)
        case .triangle(_, let p1, let p2, let p3, _, _, _, let lineWidth, _):
            return VTGBounds(points: [p1, p2, p3])?.expanded(by: lineWidth / 2)
        case .path(_, let commands, _, _, let lineWidth, _, _):
            return VTGBounds(points: commands.boundsPoints)?.expanded(by: lineWidth / 2)
        case .rect(_, let x, let y, let width, let height, _, _, _, _, let lineWidth, _):
            return VTGBounds(minX: x, minY: y, maxX: x + width, maxY: y + height).expanded(by: lineWidth / 2)
        case .circle(_, let cx, let cy, let radius, _, _, let lineWidth):
            return VTGBounds(minX: cx - radius, minY: cy - radius, maxX: cx + radius, maxY: cy + radius).expanded(by: lineWidth / 2)
        case .ellipse(_, let cx, let cy, let rx, let ry, _, _, let lineWidth):
            return VTGBounds(minX: cx - rx, minY: cy - ry, maxX: cx + rx, maxY: cy + ry).expanded(by: lineWidth / 2)
        case .text(_, let x, let y, let value, _, let size):
            let width = max(size, Double(value.count) * size * 0.6)
            return VTGBounds(minX: x, minY: y, maxX: x + width, maxY: y + size)
        case .image(_, let x, let y, let width, let height, _, _, _, _):
            return VTGBounds(minX: x, minY: y, maxX: x + width, maxY: y + height)
        case .sprite(_, let assetID, let x, let y, _, let scale, let anchorX, let anchorY):
            guard let size = spriteSize(assetID: assetID) else {
                return nil
            }
            let width = size.width * scale
            let height = size.height * scale
            return VTGBounds(
                minX: x - width * anchorX,
                minY: y - height * anchorY,
                maxX: x + width * (1 - anchorX),
                maxY: y + height * (1 - anchorY)
            )
        }
    }

    private func spriteSize(assetID: String) -> (width: Double, height: Double)? {
        if let asset = spriteAssets[assetID] {
            return (asset.width, asset.height)
        }
        if let asset = vectorSpriteAssets[assetID] {
            return (asset.width, asset.height)
        }
        if let asset = indexedSpriteAssets[assetID] {
            return (Double(asset.width), Double(asset.height))
        }
        return nil
    }
}

private struct VTGBounds {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = min(minX, maxX)
        self.minY = min(minY, maxY)
        self.maxX = max(minX, maxX)
        self.maxY = max(minY, maxY)
    }

    init?(points: [VTGPoint]) {
        guard let first = points.first else {
            return nil
        }
        minX = first.x
        minY = first.y
        maxX = first.x
        maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
    }

    func expanded(by amount: Double) -> VTGBounds {
        VTGBounds(minX: minX - amount, minY: minY - amount, maxX: maxX + amount, maxY: maxY + amount)
    }

    func intersects(_ other: VTGBounds) -> Bool {
        maxX >= other.minX && other.maxX >= minX && maxY >= other.minY && other.maxY >= minY
    }
}

private extension VTGCurve {
    var controlBoundsPoints: [VTGPoint] {
        switch self {
        case .quadratic(let start, let control, let end):
            return [start, control, end]
        case .cubic(let start, let control1, let control2, let end):
            return [start, control1, control2, end]
        }
    }
}

private extension Array where Element == VTGPathCommand {
    var boundsPoints: [VTGPoint] {
        flatMap { command -> [VTGPoint] in
            switch command {
            case .move(let point), .line(let point):
                return [point]
            case .quadratic(let control, let end):
                return [control, end]
            case .cubic(let control1, let control2, let end):
                return [control1, control2, end]
            case .close:
                return []
            }
        }
    }
}
