import Foundation

/// Maps VTG pixel coordinates into terminal grid cells.
public struct VTGMouseCoordinateMapper: Equatable {
    public var columns: Int
    public var rows: Int
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(columns: Int, rows: Int, canvasWidth: Double, canvasHeight: Double) {
        self.columns = columns
        self.rows = rows
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    /// Return the clamped zero-based cell and pixel position for top-left-origin pixels.
    public func cellPosition(pixelX: Double, pixelY: Double) -> VTGMouseCellPosition? {
        guard columns > 0, rows > 0, canvasWidth > 0, canvasHeight > 0 else {
            return nil
        }
        let clampedX = min(max(pixelX, 0), canvasWidth)
        let clampedY = min(max(pixelY, 0), canvasHeight)
        let cellWidth = canvasWidth / Double(columns)
        let cellHeight = canvasHeight / Double(rows)
        guard cellWidth > 0, cellHeight > 0 else {
            return nil
        }

        let col = min(max(0, Int(clampedX / cellWidth)), columns - 1)
        let row = min(max(0, Int(clampedY / cellHeight)), rows - 1)
        return VTGMouseCellPosition(
            gridCol: col,
            gridRow: row,
            pixelX: Int(clampedX),
            pixelY: Int(clampedY)
        )
    }

    /// Return a VTG mouse snapshot using one-based cell coordinates for the wire protocol.
    public func snapshot(pixelX: Double, pixelY: Double, modifiers: String) -> VTGMouseSnapshot? {
        guard let position = cellPosition(pixelX: pixelX, pixelY: pixelY) else {
            return nil
        }
        return VTGMouseSnapshot(
            x: position.pixelX,
            y: position.pixelY,
            cellX: position.gridCol + 1,
            cellY: position.gridRow + 1,
            modifiers: modifiers
        )
    }

    /// Return a VTG mouse snapshot using typed modifiers.
    public func snapshot(pixelX: Double, pixelY: Double, modifiers: VTGMouseModifiers) -> VTGMouseSnapshot? {
        snapshot(pixelX: pixelX, pixelY: pixelY, modifiers: modifiers.wireValue)
    }
}
