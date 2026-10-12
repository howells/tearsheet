import AppKit

/// The darkroom palette and type from the Paper file: graphite chrome, paper
/// text, one muted grey. SF stands in for the mockup's Inter.
enum Darkroom {
    static let ink = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)
    static let graphite = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.122, alpha: 1)
    static let graphiteRaised = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.180, alpha: 1)
    static let paper = NSColor(srgbRed: 0.957, green: 0.949, blue: 0.933, alpha: 1)
    static let muted = NSColor(srgbRed: 0.612, green: 0.604, blue: 0.627, alpha: 1)
    static let hairline = NSColor.white.withAlphaComponent(0.06)

    /// 13 pt body, 12 pt values, 15 pt headings, 11 pt captions.
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func valueFont() -> NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .medium) }

    /// Curves and the reduce-motion switch for every animation in the app.
    enum Motion {
        /// Entrances and exits.
        static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        /// Moving between two places on screen.
        static let easeInOut = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)

        /// A spring given as Motion gives one: roughly when it arrives, and how far it
        /// overshoots. Motion's mapping, with mass 1 and a damping ratio of 1 - bounce.
        struct Spring {
            let stiffness: CGFloat
            let damping: CGFloat

            init(visualDuration: CGFloat, bounce: CGFloat) {
                let root = 2 * .pi / (visualDuration * 1.2)
                stiffness = root * root
                damping = 2 * min(1, max(0.05, 1 - bounce)) * root
            }

            /// Things moving because the pointer asked them to.
            static let standard = Spring(visualDuration: 0.3, bounce: 0)
            /// A settle after a throw, like a new capture landing on the pile.
            static let settle = Spring(visualDuration: 0.35, bounce: 0.15)
        }

        /// With Reduce Motion on, things fade in place instead of travelling or scaling.
        static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

        static func animate(_ duration: TimeInterval, _ curve: CAMediaTimingFunction = easeOut, _ changes: () -> Void, completion: (@MainActor () -> Void)? = nil) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = curve
                context.allowsImplicitAnimation = true
                changes()
            }, completionHandler: completion.map { done in { MainActor.assumeIsolated(done) } })
        }

        /// Grows a layer-backed view's layer from `scale` about its centre, with a fade
        /// unless the caller fades the whole window instead.
        static func popIn(_ view: NSView, from scale: CGFloat = 0.96, duration: TimeInterval = 0.2, fades: Bool = true) {
            guard let layer = view.layer else { return }
            var animations: [CAAnimation] = []
            if fades {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                animations.append(fade)
            }
            if !reduced {
                let grow = CABasicAnimation(keyPath: "transform")
                grow.fromValue = NSValue(caTransform3D: scaled(scale, about: CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)))
                grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                animations.append(grow)
            }
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.timingFunction = easeOut
            layer.add(group, forKey: "popIn")
        }

        /// AppKit pins a backing layer's anchor at its corner, so scale about the centre by hand.
        private static func scaled(_ scale: CGFloat, about centre: CGPoint) -> CATransform3D {
            var t = CATransform3DMakeTranslation(centre.x, centre.y, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            return CATransform3DTranslate(t, -centre.x, -centre.y, 0)
        }
    }

    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = paper) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font(size, weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

/// The one button in Tearsheet's chrome. Visual size follows the mockup; the
/// clickable area is padded out to at least 44 points tall.
final class DarkroomButton: NSControl {
    enum Style {
        /// Paper fill, ink text: the action a screen leads with.
        case primary
        /// Raised graphite with a hairline: secondary actions in windows.
        case secondary
        /// Translucent graphite over an image (thumbnail hover).
        case glass
        /// Quiet white tint, for inline actions inside a settings row.
        case tinted
    }

    var title: String { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var handler: (() -> Void)?
    private let style: Style
    private let pill: Bool
    private let fixedWidth: CGFloat?
    private var isPressed = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }

    init(_ title: String, style: Style, pill: Bool = false, width: CGFloat? = nil, handler: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.pill = pill
        fixedWidth = width
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var faceHeight: CGFloat { style == .tinted ? 28 : 32 }
    private var titleFont: NSFont { Darkroom.font(13, style == .primary ? .semibold : .medium) }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: titleFont])
        let padding: CGFloat = style == .primary ? 20 : style == .tinted ? 12 : 16
        return NSSize(width: fixedWidth ?? ceil(text.width) + padding * 2, height: 44)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func draw(_ dirtyRect: NSRect) {
        let face = CGRect(x: 0, y: (bounds.height - faceHeight) / 2, width: bounds.width, height: faceHeight).insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = pill ? faceHeight / 2 : style == .tinted ? 7 : 8
        let shape = NSBezierPath(roundedRect: face, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        if style == .primary || style == .glass, pill {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowBlurRadius = 14
            shadow.set()
        }
        fill.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let rim {
            rim.setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
        if isPressed || isHovered {
            (style == .primary ? NSColor.black.withAlphaComponent(isPressed ? 0.12 : 0.05) : NSColor.white.withAlphaComponent(isPressed ? 0.1 : 0.05)).setFill()
            shape.fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: style == .primary ? Darkroom.ink : Darkroom.paper]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private var fill: NSColor {
        switch style {
        case .primary: Darkroom.paper
        case .secondary: Darkroom.graphiteRaised
        case .glass: Darkroom.graphite.withAlphaComponent(0.72)
        case .tinted: NSColor.white.withAlphaComponent(0.1)
        }
    }

    private var rim: NSColor? {
        switch style {
        case .primary, .tinted: nil
        case .secondary: NSColor.white.withAlphaComponent(0.1)
        case .glass: NSColor.white.withAlphaComponent(0.25)
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        var inside = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            isPressed = inside
            if next.type == .leftMouseUp { break }
        }
        isPressed = false
        if inside { handler?() }
    }

    override func accessibilityPerformPress() -> Bool {
        handler?()
        return true
    }
}

/// A 26-point round icon button on translucent graphite, in a 44-point slot (thumbnail corners).
final class DarkroomIconButton: NSControl {
    private let icon: DarkroomIcon
    private let handler: () -> Void
    private var isPressed = false { didSet { needsDisplay = true } }

    init(_ icon: DarkroomIcon, label: String, handler: @escaping () -> Void) {
        self.icon = icon
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = label
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 44), heightAnchor.constraint(equalToConstant: 44)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: CGRect(x: bounds.midX - 13, y: bounds.midY - 13, width: 26, height: 26))
        Darkroom.graphite.withAlphaComponent(isPressed ? 0.9 : 0.72).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.2).setStroke()
        circle.lineWidth = 0.5
        circle.stroke()
        icon.draw(in: bounds, color: Darkroom.paper, side: icon == .close ? 14 : 16)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        var inside = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            isPressed = inside
            if next.type == .leftMouseUp { break }
        }
        isPressed = false
        if inside { handler() }
    }

    override func accessibilityPerformPress() -> Bool {
        handler()
        return true
    }
}

/// A small dark label pill: size readouts, status and badges over images.
final class DarkroomPill: NSView {
    private let label: NSTextField

    init(_ text: String, font: NSFont = Darkroom.font(12, .medium)) {
        label = Darkroom.label(text, size: 12, weight: .medium)
        label.font = font
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Darkroom.graphite.withAlphaComponent(0.88).cgColor
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.borderWidth = 0.5
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}

/// Line icons from the mockup, drawn on an 18-point grid with a 1.6-point stroke.
enum DarkroomIcon {
    case arrow, rectangle, text, counter, pixelate, highlighter, crop, close, pencil, folder, check

    /// Path in a flipped (y-down) box of `side` points, matching the SVG source.
    func path(side: CGFloat = 18) -> (path: NSBezierPath, width: CGFloat) {
        let p = NSBezierPath()
        var width: CGFloat = 1.6
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.line(to: CGPoint(x: x, y: y)) }
        switch self {
        case .arrow:
            m(3.5, 14.5); l(14, 4)
            m(7, 3.8); l(14.2, 3.8); l(14.2, 11)
        case .rectangle:
            p.appendRoundedRect(CGRect(x: 2.8, y: 4, width: 12.4, height: 10), xRadius: 2, yRadius: 2)
        case .text:
            m(3.5, 4.5); l(14.5, 4.5); m(9, 4.5); l(9, 14.5)
        case .counter:
            p.appendOval(in: CGRect(x: 2.4, y: 2.4, width: 13.2, height: 13.2))
            m(8, 7.2); l(9.4, 6.2); l(9.4, 12)
        case .pixelate:
            p.appendRoundedRect(CGRect(x: 3, y: 3, width: 12, height: 12), xRadius: 2, yRadius: 2)
            for v: CGFloat in [7, 11] { m(v, 3); l(v, 15); m(3, v); l(15, v) }
        case .highlighter:
            m(11.5, 3.2); l(14.8, 6.5); l(8.6, 12.7); l(5.3, 9.4); p.close()
            m(5.3, 9.4); l(3.2, 14.8); l(8.6, 12.7)
        case .crop:
            m(5, 1.8); l(5, 13); l(16.2, 13)
            m(1.8, 5); l(13, 5); l(13, 16.2)
        case .close:
            // 10-point source grid, centred in 18.
            m(5.5, 5.5); l(12.5, 12.5); m(12.5, 5.5); l(5.5, 12.5)
        case .pencil:
            // 12-point source grid, offset by 3 to centre in 18.
            m(11.2, 4.6); l(13.4, 6.8); l(7.1, 13.1); l(4.2, 13.8); l(4.9, 10.9); p.close()
            width = 1.4
        case .folder:
            m(1.5, 4.2); l(1.5, 12.2); l(14.5, 12.2); l(14.5, 5.4); l(7.7, 5.4); l(6.1, 3.2); l(3.1, 3.2); l(1.5, 4.2)
            width = 1.4
        case .check:
            m(2.5, 7.4); l(5.6, 10.4); l(11.5, 3.8)
        }
        if side != 18 { p.transform(using: AffineTransform(scale: side / 18)) }
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        return (p, width)
    }

    /// Draws centred in `rect` of a flipped view.
    func draw(in rect: CGRect, color: NSColor, side: CGFloat = 18) {
        let (path, width) = path(side: side)
        path.transform(using: AffineTransform(translationByX: rect.midX - side / 2, byY: rect.midY - side / 2))
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}
