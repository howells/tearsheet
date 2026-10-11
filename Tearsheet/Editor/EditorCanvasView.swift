import AppKit

/// Shows the capture fitted to the window and turns mouse and keyboard input
/// into annotation edits. Everything is stored in capture pixels.
final class EditorCanvasView: NSView, NSTextFieldDelegate {
    let base: CGImage
    let scale: CGFloat

    private(set) var document: AnnotationDocument {
        didSet { cachedRender = nil; needsDisplay = true }
    }

    var tool: AnnotationTool = .arrow {
        didSet { if tool != oldValue { selectedID = nil; onStateChange?() } }
    }
    var color: AnnotationColor = .red {
        didSet { restyleSelection(); textField?.textColor = color.nsColor; onStateChange?() }
    }
    var size: StrokeSize = .medium {
        didSet { restyleSelection(); onStateChange?() }
    }
    var textStyle: TextStyle = .outline {
        didSet { restyleSelection(); onStateChange?() }
    }

    var onStateChange: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private var selectedID: UUID? { didSet { needsDisplay = true } }
    private var draft: Annotation?
    private var cropDraft: CGRect?
    /// Annotation being moved or retyped: left out of the cached render and drawn live.
    private var lifted: Annotation?
    private var cachedRender: CGImage?
    private var cachedWithout: UUID?

    private enum Drag {
        case creating(start: CGPoint)
        case moving(last: CGPoint, before: AnnotationDocument)
        case cropping(start: CGPoint)
    }
    private var drag: Drag?

    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    private var textEditingID: UUID?

    init(base: CGImage, scale: CGFloat, document: AnnotationDocument) {
        self.base = base
        self.scale = scale
        self.document = document
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: Geometry

    private var imagePixelSize: CGSize { CGSize(width: base.width, height: base.height) }

    /// Points per capture pixel: fit the window, never larger than actual size.
    private var zoom: CGFloat {
        let padding: CGFloat = 24
        let available = CGSize(width: max(bounds.width - padding * 2, 1), height: max(bounds.height - padding * 2, 1))
        return min(available.width / imagePixelSize.width, available.height / imagePixelSize.height, 1 / scale)
    }

    private var imageFrame: CGRect {
        let size = CGSize(width: imagePixelSize.width * zoom, height: imagePixelSize.height * zoom)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height).integral
    }

    private func toImage(_ point: CGPoint) -> CGPoint {
        let frame = imageFrame
        return CGPoint(x: (point.x - frame.minX) / zoom, y: (point.y - frame.minY) / zoom)
    }

    private func toView(_ point: CGPoint) -> CGPoint {
        let frame = imageFrame
        return CGPoint(x: frame.minX + point.x * zoom, y: frame.minY + point.y * zoom)
    }

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imagePixelSize.width), y: min(max(point.y, 0), imagePixelSize.height))
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        repositionTextField()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        AnnotationColor.inkColor.setFill()
        bounds.fill()

        let hiddenID = lifted?.id
        if cachedRender == nil || cachedWithout != hiddenID {
            let visible = document.annotations.filter { $0.id != hiddenID }
            cachedRender = AnnotationRenderer.composite(base: base, annotations: visible, scale: scale)
            cachedWithout = hiddenID
        }

        let frame = imageFrame
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY)
        context.scaleBy(x: zoom, y: zoom)
        context.interpolationQuality = .high
        if let cachedRender { context.draw(cachedRender, in: CGRect(origin: .zero, size: imagePixelSize)) }

        if let lifted, textEditingID != lifted.id {
            AnnotationRenderer.draw(lifted, number: document.counterNumber(for: lifted.id), in: context, scale: scale)
        }
        if let draft {
            AnnotationRenderer.draw(draft, number: document.counterNumber(for: draft.id), in: context, scale: scale)
        }
        if let selectedID, let selected = (lifted?.id == selectedID ? lifted : document.annotations.first { $0.id == selectedID }) {
            // A hairline outline with square corner handles, in paper so it reads against any ink.
            let outline = selected.bounds(scale: scale).insetBy(dx: -4 / zoom, dy: -4 / zoom)
            let handle = 8 / zoom
            context.setStrokeColor(AnnotationColor.paperColor.cgColor)
            context.setLineWidth(1 / zoom)
            context.stroke(outline)
            context.setFillColor(AnnotationColor.paperColor.cgColor)
            context.setShadow(offset: .zero, blur: 2 / zoom, color: NSColor.black.withAlphaComponent(0.5).cgColor)
            for corner in [CGPoint(x: outline.minX, y: outline.minY), CGPoint(x: outline.maxX, y: outline.minY),
                           CGPoint(x: outline.minX, y: outline.maxY), CGPoint(x: outline.maxX, y: outline.maxY)] {
                context.fill(CGRect(x: corner.x - handle / 2, y: corner.y - handle / 2, width: handle, height: handle))
            }
            context.setShadow(offset: .zero, blur: 0)
        }
        if let crop = cropDraft ?? document.crop {
            context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            context.addRect(CGRect(origin: .zero, size: imagePixelSize))
            context.addRect(crop)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1 / zoom)
            context.stroke(crop)
        }
        context.restoreGState()
    }

    // MARK: Editing

    private func setDocument(_ new: AnnotationDocument) {
        let old = document
        undoManager?.registerUndo(withTarget: self) { canvas in
            MainActor.assumeIsolated { canvas.setDocument(old) }
        }
        document = new
    }

    private func change(_ edit: (inout AnnotationDocument) -> Void) {
        var copy = document
        edit(&copy)
        setDocument(copy)
    }

    private func restyleSelection() {
        guard let selectedID, let index = document.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        change { document in
            document.annotations[index].color = color
            document.annotations[index].size = size
            if case let .text(origin, string, _) = document.annotations[index].shape {
                document.annotations[index].shape = .text(origin: origin, string: string, style: textStyle)
            }
        }
    }

    private func deleteSelection() {
        guard let selectedID else { return }
        change { $0.annotations.removeAll { $0.id == selectedID } }
        self.selectedID = nil
    }

    private func topAnnotation(at point: CGPoint) -> Annotation? {
        document.annotations.last { $0.contains(point, tolerance: 4 / zoom, scale: scale) }
    }

    /// Counters dropped near an arrow's tail or a rectangle's corner land exactly on it.
    private func snapped(_ point: CGPoint) -> CGPoint {
        var anchors: [CGPoint] = []
        for annotation in document.annotations {
            switch annotation.shape {
            case let .arrow(from, _): anchors.append(from)
            case let .rectangle(rect):
                anchors += [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            default: break
            }
        }
        let reach = size.counterDiameter * scale * 0.75
        let nearest = anchors.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }
        guard let nearest, hypot(nearest.x - point.x, nearest.y - point.y) <= reach else { return point }
        return nearest
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textField != nil {
            window?.makeFirstResponder(self)
            return
        }
        window?.makeFirstResponder(self)
        let point = toImage(convert(event.locationInWindow, from: nil))

        if tool != .crop, let hit = topAnnotation(at: point) {
            if event.clickCount == 2, case let .text(origin, string, style) = hit.shape {
                textStyle = style
                beginText(at: origin, string: string, replacing: hit)
                return
            }
            selectedID = hit.id
            lifted = hit
            drag = .moving(last: point, before: document)
            return
        }

        selectedID = nil
        let start = clampToImage(point)
        switch tool {
        case .counter:
            change { $0.annotations.append(Annotation(shape: .counter(center: snapped(start)), color: color, size: size)) }
        case .text:
            beginText(at: start, string: "", replacing: nil)
        case .crop:
            drag = .cropping(start: start)
        default:
            drag = .creating(start: start)
            draft = makeDraft(from: start, to: start)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToImage(toImage(convert(event.locationInWindow, from: nil)))
        switch drag {
        case let .creating(start):
            if case let .highlighter(points)? = draft?.shape {
                draft?.shape = .highlighter(points + [point])
            } else {
                draft = makeDraft(from: start, to: constrained(point, from: start, shift: event.modifierFlags.contains(.shift)))
            }
        case let .moving(last, before):
            lifted = lifted?.translated(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            drag = .moving(last: point, before: before)
        case let .cropping(start):
            cropDraft = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        case nil:
            return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; needsDisplay = true }
        switch drag {
        case .creating:
            if let draft, isMeaningful(draft) { change { $0.annotations.append(draft) } }
            draft = nil
        case let .moving(_, before):
            guard let moved = lifted else { return }
            lifted = nil
            var after = before
            if let index = after.annotations.firstIndex(where: { $0.id == moved.id }) { after.annotations[index] = moved }
            if after.annotations != before.annotations { setDocument(after) }
        case .cropping:
            if let cropDraft, cropDraft.width > 8, cropDraft.height > 8 { change { $0.crop = cropDraft.integral } }
            cropDraft = nil
        case nil:
            break
        }
    }

    private func makeDraft(from start: CGPoint, to end: CGPoint) -> Annotation {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let shape: Annotation.Shape = switch tool {
        case .rectangle: .rectangle(rect)
        case .pixelate: .pixelate(rect)
        case .highlighter: .highlighter([start])
        default: .arrow(from: start, to: end)
        }
        return Annotation(id: draft?.id ?? UUID(), shape: shape, color: color, size: size)
    }

    /// Shift keeps rectangles square and arrows on 45° steps.
    private func constrained(_ point: CGPoint, from start: CGPoint, shift: Bool) -> CGPoint {
        guard shift else { return point }
        let dx = point.x - start.x, dy = point.y - start.y
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + side * (dx < 0 ? -1 : 1), y: start.y + side * (dy < 0 ? -1 : 1))
    }

    private func isMeaningful(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case let .arrow(from, to): hypot(to.x - from.x, to.y - from.y) > 4 * scale
        case let .rectangle(rect), let .pixelate(rect): rect.width > 3 * scale && rect.height > 3 * scale
        case .highlighter: true
        case .text, .counter: true
        }
    }

    // MARK: Text

    private func beginText(at origin: CGPoint, string: String, replacing existing: Annotation?) {
        textOrigin = origin
        textEditingID = existing?.id ?? UUID()
        lifted = existing
        selectedID = nil

        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.textColor = color.nsColor
        field.font = .systemFont(ofSize: size.textPoints * scale * zoom, weight: .semibold)
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        textField = field
        addSubview(field)
        repositionTextField()
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func repositionTextField() {
        guard let textField else { return }
        textField.font = .systemFont(ofSize: size.textPoints * scale * zoom, weight: .semibold)
        textField.sizeToFit()
        let width = max(textField.frame.width + 16, 60)
        let topLeft = toView(textOrigin)
        textField.frame = CGRect(x: topLeft.x - 2, y: topLeft.y - textField.frame.height, width: width, height: textField.frame.height)
    }

    func controlTextDidChange(_ notification: Notification) { repositionTextField() }

    func controlTextDidEndEditing(_ notification: Notification) { finishText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    /// Commits any text being typed. Safe to call when nothing is being edited.
    func finishText() {
        guard let field = textField, let id = textEditingID else { return }
        textField = nil
        textEditingID = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        lifted = nil
        change { document in
            let index = document.annotations.firstIndex { $0.id == id }
            if let index { document.annotations.remove(at: index) }
            guard !string.isEmpty else { return }
            let annotation = Annotation(id: id, shape: .text(origin: textOrigin, string: string, style: textStyle), color: color, size: size)
            document.annotations.insert(annotation, at: index ?? document.annotations.endIndex)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case 53: // Escape
            if selectedID != nil { selectedID = nil } else { onCancel?() }
            return
        case 51, 117: // Delete, forward delete
            deleteSelection()
            return
        case 36, 76: // Return, Enter
            onCommit?()
            return
        default:
            break
        }
        guard let character = event.charactersIgnoringModifiers?.lowercased() else { return }
        if let tool = AnnotationTool.allCases.first(where: { $0.key == character }) {
            self.tool = tool
        } else if let number = Int(character), let color = AnnotationColor(rawValue: number - 1) {
            self.color = color
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) { onCommit?() }
}
