import Foundation

/// Synthesizes one logical click from a platform down/up mouse pair.
///
/// Embedding views still capture native mouse events, but this helper keeps the
/// protocol-level debounce thresholds in SwiftTerm so all VTG hosts behave the
/// same way.
public final class VTGMouseClickSynthesizer {
    private struct DownEvent {
        var button: Int
        var snapshot: VTGMouseSnapshot
        var timestamp: TimeInterval
    }

    public var maximumClickInterval: TimeInterval
    public var maximumClickDistance: Double

    private var downEvent: DownEvent?

    public init(
        maximumClickInterval: TimeInterval = 0.6,
        maximumClickDistance: Double = 8
    ) {
        self.maximumClickInterval = maximumClickInterval
        self.maximumClickDistance = maximumClickDistance
    }

    /// Record a possible click start.
    public func recordDown(
        button: Int,
        snapshot: VTGMouseSnapshot,
        timestamp: TimeInterval
    ) {
        downEvent = DownEvent(button: button, snapshot: snapshot, timestamp: timestamp)
    }

    /// Return true when the recorded down event and this up event form a click.
    public func shouldSynthesizeClick(
        button: Int,
        snapshot: VTGMouseSnapshot,
        timestamp: TimeInterval
    ) -> Bool {
        guard let downEvent,
              downEvent.button == button else {
            return false
        }
        let elapsed = timestamp - downEvent.timestamp
        let distance = hypot(
            Double(snapshot.x - downEvent.snapshot.x),
            Double(snapshot.y - downEvent.snapshot.y)
        )
        return elapsed <= maximumClickInterval && distance <= maximumClickDistance
    }

    /// Clear the current pending down event.
    public func reset() {
        downEvent = nil
    }
}
