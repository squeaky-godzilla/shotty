import AppKit
import ScreenCaptureKit

final class WindowPickerOverlayController {
    private var overlayWindow: NSWindow?
    private var completion: ((NSImage?) -> Void)?
    private var retainCycle: WindowPickerOverlayController?
    private var scContent: SCShareableContent?

    static func show(content: SCShareableContent, completion: @escaping (NSImage?) -> Void) {
        let controller = WindowPickerOverlayController()
        controller.retainCycle = controller
        controller.scContent = content
        controller.completion = completion

        let windows = content.windows
            .filter { $0.isOnScreen && $0.frame.width > 10 && $0.frame.height > 10 }
        slog("WindowPicker: \(windows.count) SCK windows found")
        controller.present(windows: windows)
    }

    private func present(windows: [SCWindow]) {
        guard let screen = NSScreen.main else { finish(nil); return }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = WindowPickerView(screen: screen, windows: windows) { [weak self] picked in
            self?.didPick(picked)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow = win
    }

    private func didPick(_ picked: SCWindow?) {
        if let view = overlayWindow?.contentView as? WindowPickerView {
            view.teardown()
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        guard let picked else { finish(nil); return }
        captureWindow(picked)
    }

    private func finish(_ image: NSImage?) {
        let cb = completion
        completion = nil
        retainCycle = nil
        scContent = nil
        cb?(image)
    }

    // MARK: - Capture via SCK

    private func captureWindow(_ scWindow: SCWindow) {
        guard let content = scContent else { finish(nil); return }

        let display = content.displays.first(where: { d in
            guard let ns = d.nsScreen else { return false }
            return ns.frame.intersects(scWindow.frame)
        }) ?? content.displays.first

        let scale = display?.nsScreen?.backingScaleFactor ?? 2.0
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let cfg = SCStreamConfiguration()
        cfg.width  = max(1, Int(scWindow.frame.width  * scale))
        cfg.height = max(1, Int(scWindow.frame.height * scale))
        cfg.showsCursor = false

        // Small delay so overlay is fully gone before capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            slog("captureWindow \(cfg.width)x\(cfg.height) wid=\(scWindow.windowID)")
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { [weak self] cgImage, error in
                DispatchQueue.main.async {
                    if let cgImage {
                        self?.finish(NSImage(cgImage: cgImage, size: scWindow.frame.size))
                    } else {
                        slog("captureWindow error: \(error?.localizedDescription ?? "nil")")
                        self?.finish(nil)
                    }
                }
            }
        }
    }
}

// MARK: - Window picker view

final class WindowPickerView: NSView {
    private let screen: NSScreen
    private let windows: [SCWindow]
    private let onPick: (SCWindow?) -> Void
    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, windows: [SCWindow], onPick: @escaping (SCWindow?) -> Void) {
        self.screen = screen
        self.windows = windows
        self.onPick = onPick
        super.init(frame: screen.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        setupTracking()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func teardown() {
        if let area = trackingArea {
            removeTrackingArea(area)
            trackingArea = nil
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override var isFlipped: Bool { false }

    // SCWindow.frame: top-left origin in global CG coords → convert to view-local bottom-left.
    private func viewRect(for w: SCWindow) -> CGRect {
        let f = w.frame
        return CGRect(
            x: f.origin.x - screen.frame.origin.x,
            y: screen.frame.height - (f.origin.y - screen.frame.origin.y) - f.height,
            width: f.width, height: f.height
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onPick(nil) }
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let old = hoveredIndex
        hoveredIndex = windows.indices.last(where: { viewRect(for: windows[$0]).contains(pt) })
        if old != hoveredIndex { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        onPick(hoveredIndex.map { windows[$0] })
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, w) in windows.enumerated() {
            let r = viewRect(for: w)
            guard r.intersects(dirtyRect), i == hoveredIndex else { continue }

            NSColor.systemBlue.withAlphaComponent(0.25).setFill()
            r.fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()

            let title = w.owningApplication?.applicationName ?? ""
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .backgroundColor: NSColor.black.withAlphaComponent(0.6)
            ]
            NSAttributedString(string: "  \(title)  ", attributes: attrs)
                .draw(at: CGPoint(x: r.minX + 4, y: r.maxY - 20))
        }

        let hint = "Click a window to capture   •   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        let str = NSAttributedString(string: hint, attributes: attrs)
        str.draw(at: CGPoint(x: (bounds.width - str.size().width) / 2, y: 24))
    }
}
