import Foundation

/// Viewport, layer lookup, and hit-testing helpers for the retained VTG scene.
extension VTGGraphicsScene {
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

    /// Return the fixed-resolution viewport mode for a layer, if one is active.
    public func viewportMode(for layer: Int) -> VTGViewportMode? {
        viewportModes[layer]
    }

    /// Return the explicit fixed-viewport placement override, if one is active.
    public func viewportScale(for layer: Int) -> VTGViewportScale? {
        viewportScales[layer]
    }

    /// Resolve fixed-resolution viewport state into concrete renderer math.
    ///
    /// The transform maps a layer's virtual coordinates into the live graphics
    /// canvas. Renderers apply this before layer scroll offsets so scroll
    /// remains expressed in the same virtual coordinate system as drawing.
    public func viewportTransform(for layer: Int, canvasWidth: Double, canvasHeight: Double) -> VTGViewportTransform? {
        guard let mode = viewportModes[layer], canvasWidth > 0, canvasHeight > 0 else {
            return nil
        }
        if let override = viewportScales[layer] {
            return VTGViewportTransform(
                x: override.x,
                y: override.y,
                scaleX: override.scale,
                scaleY: override.scale,
                width: mode.width * override.scale,
                height: mode.height * override.scale
            )
        }

        let scaleX = canvasWidth / mode.width
        let scaleY = canvasHeight / mode.height
        let resolvedScaleX: Double
        let resolvedScaleY: Double
        switch mode.scaleMode {
        case .fit:
            let scale = min(scaleX, scaleY)
            resolvedScaleX = scale
            resolvedScaleY = scale
        case .fill:
            let scale = max(scaleX, scaleY)
            resolvedScaleX = scale
            resolvedScaleY = scale
        case .integer:
            let fitScale = min(scaleX, scaleY)
            let scale = fitScale >= 1 ? floor(fitScale) : fitScale
            resolvedScaleX = scale
            resolvedScaleY = scale
        case .stretch:
            resolvedScaleX = scaleX
            resolvedScaleY = scaleY
        }

        let width = mode.width * resolvedScaleX
        let height = mode.height * resolvedScaleY
        return VTGViewportTransform(
            x: (canvasWidth - width) / 2,
            y: (canvasHeight - height) / 2,
            scaleX: resolvedScaleX,
            scaleY: resolvedScaleY,
            width: width,
            height: height
        )
    }

    /// Map a physical canvas pixel to the topmost fixed-viewport layer.
    public func viewportMousePosition(at point: VTGPoint, canvasWidth: Double, canvasHeight: Double) -> VTGViewportMousePosition? {
        VTGLayerModel.scrollableRange.reversed().compactMap { layer -> VTGViewportMousePosition? in
            guard let transform = viewportTransform(for: layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight),
                  point.x >= transform.x,
                  point.x <= transform.x + transform.width,
                  point.y >= transform.y,
                  point.y <= transform.y + transform.height else {
                return nil
            }
            let offset = offset(for: layer)
            return VTGViewportMousePosition(
                layer: layer,
                x: ((point.x - transform.x) / transform.scaleX) - offset.x,
                y: ((point.y - transform.y) / transform.scaleY) - offset.y
            )
        }.first
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
