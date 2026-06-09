import Foundation

/// Hit-region lookup helpers for the retained VTG scene.
extension VTGGraphicsScene {
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

    /// Return the topmost hit region while accounting for fixed-viewport layers.
    public func hitRegion(at point: VTGPoint, canvasWidth: Double, canvasHeight: Double) -> VTGHitRegion? {
        hitRegions.values
            .filter { region in
                let hitPoint: VTGPoint
                if let viewport = viewportTransform(for: region.layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight) {
                    guard point.x >= viewport.x,
                          point.x <= viewport.x + viewport.width,
                          point.y >= viewport.y,
                          point.y <= viewport.y + viewport.height else {
                        return false
                    }
                    let offset = offset(for: region.layer)
                    hitPoint = VTGPoint(
                        x: ((point.x - viewport.x) / viewport.scaleX) - offset.x,
                        y: ((point.y - viewport.y) / viewport.scaleY) - offset.y
                    )
                } else {
                    let offset = offset(for: region.layer)
                    hitPoint = VTGPoint(x: point.x - offset.x, y: point.y - offset.y)
                }

                guard hitPoint.x >= region.x,
                      hitPoint.x <= region.x + region.width,
                      hitPoint.y >= region.y,
                      hitPoint.y <= region.y + region.height else {
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
}
