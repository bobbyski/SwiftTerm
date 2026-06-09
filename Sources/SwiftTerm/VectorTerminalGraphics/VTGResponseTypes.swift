import Foundation

/// Pixel dimensions of the VTG drawing canvas.
public struct VTGCanvasSize: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Mouse or pointer state encoded into a VTG mouse event.
public struct VTGMouseEventPayload: Equatable {
    public var type: String
    public var button: Int
    public var x: Int
    public var y: Int
    public var cellX: Int
    public var cellY: Int
    public var modifiers: String
    public var scrollX: Int?
    public var scrollY: Int?
    public var hitID: String?
    public var targetID: String?
    public var viewportLayer: Int?
    public var virtualX: Int?
    public var virtualY: Int?

    public init(
        type: String,
        button: Int,
        x: Int,
        y: Int,
        cellX: Int,
        cellY: Int,
        modifiers: String,
        scrollX: Int? = nil,
        scrollY: Int? = nil,
        hitID: String? = nil,
        targetID: String? = nil,
        viewportLayer: Int? = nil,
        virtualX: Int? = nil,
        virtualY: Int? = nil
    ) {
        self.type = type
        self.button = button
        self.x = x
        self.y = y
        self.cellX = cellX
        self.cellY = cellY
        self.modifiers = modifiers
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.hitID = hitID
        self.targetID = targetID
        self.viewportLayer = viewportLayer
        self.virtualX = virtualX
        self.virtualY = virtualY
    }
}
