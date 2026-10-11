import AppKit

/// The editor's top bar: tools on the left, after the window controls; colour,
/// size and (for text) style on the right. Drawn as one view from the mockup's
/// measurements, with a 44-point hit slot per control.
final class EditorToolbarView: NSView {
    var tool: AnnotationTool = .arrow { didSet { needsLayout = true; needsDisplay = true } }
    var color: AnnotationColor = .red { didSet { needsDisplay = true } }
    var size: StrokeSize = .medium { didSet { needsDisplay = true } }
    var textStyle: TextStyle = .outline { didSet { needsDisplay = true } }

    var onTool: ((AnnotationTool) -> Void)?
    var onColor: ((AnnotationColor) -> Void)?
    var onSize: ((StrokeSize) -> Void)?
    var onTextStyle: ((TextStyle) -> Void)?

    private enum Slot: Hashable {
        case tool(AnnotationTool), color(AnnotationColor), size(StrokeSize), style(TextStyle)
    }

    private var slots: [(slot: Slot, rect: CGRect)] = []
    private var dividers: [CGFloat] = []
    private var hovered: Slot?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        slots = []
        dividers = []
        let top = (bounds.height - 44) / 2
        // 20 pt inset, 52 pt of window controls, 20 pt gap.
        var x: CGFloat = 92
        for tool in AnnotationTool.allCases {
            slots.append((.tool(tool), CGRect(x: x, y: top, width: 44, height: 44)))
            x += 44
        }

        var right = bounds.width - 16
        if tool == .text {
            for style in [TextStyle.background, .outline] {
                right -= 36
                slots.append((.style(style), CGRect(x: right, y: top, width: 36, height: 44)))
            }
            right -= 6
            dividers.append(right - 0.5)
            right -= 7
        }
        for size in StrokeSize.allCases.reversed() {
            right -= 36
            slots.append((.size(size), CGRect(x: right, y: top, width: 36, height: 44)))
        }
        right -= 6
        dividers.append(right - 0.5)
        right -= 7
        for color in AnnotationColor.allCases.reversed() {
            right -= 32
            slots.append((.color(color), CGRect(x: right, y: top, width: 32, height: 44)))
        }

        removeAllToolTips()
        for (slot, rect) in slots {
            switch slot {
            case let .tool(tool): addToolTip(rect, owner: "\(tool.label) (\(tool.key.uppercased()))" as NSString, userData: nil)
            case let .color(color): addToolTip(rect, owner: "\(color.label) (\(color.rawValue + 1))" as NSString, userData: nil)
            case let .size(size): addToolTip(rect, owner: ["Small", "Medium", "Large"][size.rawValue] as NSString, userData: nil)
            case let .style(style): addToolTip(rect, owner: (style == .outline ? "Outlined text" : "Text on a box") as NSString, userData: nil)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Darkroom.hairline.setFill()
        CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        for x in dividers {
            NSColor.white.withAlphaComponent(0.1).setFill()
            CGRect(x: x, y: bounds.midY - 10, width: 1, height: 20).fill()
        }
        for (slot, rect) in slots { draw(slot, in: rect) }
    }

    private func draw(_ slot: Slot, in rect: CGRect) {
        let isHovered = hovered == slot
        switch slot {
        case let .tool(item):
            let face = CGRect(x: rect.midX - 18, y: rect.midY - 16, width: 36, height: 32)
            let selected = item == tool
            if selected || isHovered {
                (selected ? Darkroom.paper : NSColor.white.withAlphaComponent(0.06)).setFill()
                NSBezierPath(roundedRect: face, xRadius: 8, yRadius: 8).fill()
            }
            item.icon.draw(in: rect, color: selected ? Darkroom.ink : Darkroom.paper)

        case let .color(item):
            let selected = item == color
            let diameter: CGFloat = selected ? 20 : 16
            let dot = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
            if selected {
                // A paper ring with a 2-point graphite gap, as in the mockup.
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -2.75, dy: -2.75))
                ring.lineWidth = 1.5
                Darkroom.paper.setStroke()
                ring.stroke()
            } else if isHovered {
                NSColor.white.withAlphaComponent(0.06).setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: -5, dy: -5)).fill()
            }
            item.nsColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            if item == .graphite {
                let rim = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
                rim.lineWidth = 1
                NSColor.white.withAlphaComponent(0.35).setStroke()
                rim.stroke()
            }

        case let .size(item):
            let selected = item == size
            if selected || isHovered {
                NSColor.white.withAlphaComponent(selected ? 0.08 : 0.05).setFill()
                NSBezierPath(roundedRect: CGRect(x: rect.midX - 15, y: rect.midY - 15, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
            }
            let height = item.stroke
            (selected ? Darkroom.paper : Darkroom.muted).setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.midX - 8, y: rect.midY - height / 2, width: 16, height: height), xRadius: height / 2, yRadius: height / 2).fill()

        case let .style(item):
            let selected = item == textStyle
            if selected || isHovered {
                NSColor.white.withAlphaComponent(selected ? 0.08 : 0.05).setFill()
                NSBezierPath(roundedRect: CGRect(x: rect.midX - 15, y: rect.midY - 15, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
            }
            let ink = selected ? Darkroom.paper : Darkroom.muted
            let font = Darkroom.font(13, .bold)
            if item == .background {
                let box = CGRect(x: rect.midX - 9, y: rect.midY - 8, width: 18, height: 16)
                ink.setFill()
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
                drawLetter(in: rect, font: font, attributes: [.foregroundColor: Darkroom.graphite])
            } else {
                drawLetter(in: rect, font: font, attributes: [.foregroundColor: NSColor.clear, .strokeColor: ink, .strokeWidth: 3])
            }
        }
    }

    private func drawLetter(in rect: CGRect, font: NSFont, attributes: [NSAttributedString.Key: Any]) {
        let text = NSAttributedString(string: "A", attributes: attributes.merging([.font: font]) { $1 })
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    // MARK: Mouse

    private func slot(at event: NSEvent) -> Slot? {
        let point = convert(event.locationInWindow, from: nil)
        return slots.first { $0.rect.contains(point) }?.slot
    }

    override func mouseMoved(with event: NSEvent) {
        let slot = slot(at: event)
        if slot != hovered { hovered = slot; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let slot = slot(at: event) else {
            window?.performDrag(with: event)
            return
        }
        switch slot {
        case let .tool(tool): onTool?(tool)
        case let .color(color): onColor?(color)
        case let .size(size): onSize?(size)
        case let .style(style): onTextStyle?(style)
        }
    }
}

/// The editor's bottom bar: pixel size on the left, Save and Copy on the right.
final class EditorActionBar: NSView {
    override var isFlipped: Bool { true }

    init(pixelSize: CGSize, save: @escaping () -> Void, copy: @escaping () -> Void) {
        super.init(frame: .zero)
        let dimensions = Darkroom.label("\(Int(pixelSize.width)) × \(Int(pixelSize.height))", size: 12, weight: .medium, color: Darkroom.muted)
        dimensions.font = Darkroom.valueFont()
        dimensions.toolTip = "Pixels"
        let saveButton = DarkroomButton("Save", style: .secondary, handler: save)
        saveButton.toolTip = "Save (⌘S, hold ⌥ for 1×)"
        let copyButton = DarkroomButton("Copy", style: .primary, handler: copy)
        copyButton.toolTip = "Copy and close (⌘C or ↩)"
        for view in [dimensions, saveButton, copyButton] { addSubview(view) }
        NSLayoutConstraint.activate([
            dimensions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            dimensions.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Darkroom.hairline.setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

extension AnnotationTool {
    var icon: DarkroomIcon {
        switch self {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .text: .text
        case .counter: .counter
        case .pixelate: .pixelate
        case .highlighter: .highlighter
        case .crop: .crop
        }
    }
}

extension AnnotationColor {
    var label: String {
        switch self {
        case .red: "Red"
        case .amber: "Amber"
        case .green: "Green"
        case .blue: "Blue"
        case .graphite: "Graphite"
        case .paper: "Paper"
        }
    }
}
