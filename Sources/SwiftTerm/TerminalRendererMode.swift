/// Public renderer selection for terminal views.
///
/// This is intentionally additive: existing callers can keep using
/// `setUseMetal(_:)`, while embedders that need to reason about renderer choice
/// can use this typed surface.
public enum TerminalRendererMode: Equatable {
    /// The existing platform drawing path.
    case coreGraphics

    /// The existing Metal renderer.
    case metal

    /// Experimental SVG renderer/export path.
    ///
    /// The first implementation keeps the normal platform view visible and
    /// exposes SVG snapshots for inspection, export, and future renderer work.
    case svg
}

/// Errors thrown while changing the terminal renderer mode.
public enum TerminalRendererModeError: Error, Equatable {
    case unsupported(TerminalRendererMode)
}
