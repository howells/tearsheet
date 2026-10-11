import AppKit
import ImageIO
import TearsheetCore

/// A grid for choosing among several images found under one click or drag.
/// Click a tile to take that image, or take them all.
final class ImagePicker: NSObject {
    private let panel: PickerPanel
    private var continuation: CheckedContinuation<[ScreenImage]?, Never>?
    private var keyMonitor: Any?
    private let candidates: [ScreenImage]

    /// `preview` supplies a tile image when the original can't be loaded quickly: the frozen screen behind it.
    init(candidates: [ScreenImage], preview: (ScreenImage) -> CGImage?) {
        self.candidates = candidates
        panel = PickerPanel()
        super.init()

        let columns = min(4, candidates.count)
        let tileSize: CGFloat = 132
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        var row: [NSView] = []
        for (index, candidate) in candidates.enumerated() {
            let tile = PickerTile(candidate: candidate, preview: preview(candidate), size: tileSize)
            tile.target = self
            tile.action = #selector(pick(_:))
            tile.tag = index
            row.append(tile)
            if row.count == columns || index == candidates.count - 1 {
                grid.addRow(with: row + Array(repeating: NSGridCell.emptyContentView, count: columns - row.count))
                row = []
            }
        }

        let takeAll = NSButton(title: "Copy All \(candidates.count)", target: self, action: #selector(pickAll))
        takeAll.bezelStyle = .glass
        takeAll.controlSize = .large
        takeAll.bezelColor = AnnotationColor.paperColor
        takeAll.attributedTitle = NSAttributedString(string: takeAll.title, attributes: [
            .foregroundColor: AnnotationColor.inkColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
        ])
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .glass
        cancel.controlSize = .large
        let buttons = NSStackView(views: [NSView(), cancel, takeAll])
        buttons.spacing = 10

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])
        panel.contentView = background
        panel.setContentSize(background.fittingSize)
    }

    var windowNumber: Int { panel.windowNumber }

    func choose() async -> [ScreenImage]? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            if let screen = NSScreen.underMouse {
                let visible = screen.visibleFrame
                panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2))
            }
            panel.orderFrontRegardless()
            panel.makeKey()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                switch Int(event.keyCode) {
                case 53: self?.finish(nil); return nil
                case 36, 76: self?.pickAll(); return nil
                default: return event
                }
            }
        }
    }

    @objc private func pick(_ sender: NSButton) { finish([candidates[sender.tag]]) }
    @objc private func pickAll() { finish(candidates) }
    @objc private func cancel() { finish(nil) }

    private func finish(_ result: [ScreenImage]?) {
        guard let continuation else { return }
        self.continuation = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
        continuation.resume(returning: result)
    }
}

private final class PickerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
}

/// One candidate: its picture and the file name it would be saved under.
private final class PickerTile: NSButton {
    private let picture = NSImageView()

    init(candidate: ScreenImage, preview: CGImage?, size: CGFloat) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(Self.caption(for: candidate))

        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        picture.layer?.cornerRadius = 6
        picture.layer?.masksToBounds = true
        picture.translatesAutoresizingMaskIntoConstraints = false
        if let preview { picture.image = NSImage(cgImage: preview, size: .zero) }

        let label = NSTextField(labelWithString: Self.caption(for: candidate))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(picture)
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            picture.topAnchor.constraint(equalTo: topAnchor),
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            picture.heightAnchor.constraint(equalToConstant: size),
            label.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Stacked background layers share one rendered look; show each file itself when it loads.
        if case let .url(url) = candidate.image.source, ["http", "https"].contains(url.scheme?.lowercased()) {
            Task { [weak self] in
                guard let thumbnail = await Self.loadThumbnail(url, maxPixels: Int(size * 2)) else { return }
                self?.picture.image = NSImage(cgImage: thumbnail, size: .zero)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private static func caption(for candidate: ScreenImage) -> String {
        switch candidate.image.source {
        case let .url(url): WebImageFilename.name(for: url, mimeType: nil)
        case .svg: "Inline SVG"
        }
    }

    nonisolated private static func loadThumbnail(_ url: URL, maxPixels: Int) async -> CGImage? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
