import Foundation

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
