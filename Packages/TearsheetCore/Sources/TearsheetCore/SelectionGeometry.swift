import CoreGraphics

/// Selection maths for the capture overlay. Selections live in a display's
/// local point space (origin bottom-left, as AppKit views use); captured
/// images are addressed in pixels with the origin at the top-left.
public enum SelectionGeometry {
    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// The rectangle spanned by two drag points, kept inside `bounds`.
    public static func rect(from a: CGPoint, to b: CGPoint, within bounds: CGRect) -> CGRect {
        let a = clamp(a, to: bounds)
        let b = clamp(b, to: bounds)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Moves `rect` by `delta` without letting any edge leave `bounds`.
    public static func move(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// Converts a point-space selection to the whole-pixel rectangle of a
    /// top-left-origin image captured at `scale` pixels per point.
    public static func pixelRect(for rect: CGRect, viewHeight: CGFloat, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded()
        let maxX = (rect.maxX * scale).rounded()
        let minY = ((viewHeight - rect.maxY) * scale).rounded()
        let maxY = ((viewHeight - rect.minY) * scale).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
