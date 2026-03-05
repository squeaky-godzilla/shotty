import AppKit
import ScreenCaptureKit

final class SelectionOverlayController {
    private var overlayWindows: [NSWindow] = []
    private var completion: ((NSImage?) -> Void)?
    private var retainCycle: SelectionOverlayController?
    private var scContent: SCShareableContent?

    static func show(content: SCShareableContent, completion: @escaping (NSImage?) -> Void) {
        let controller = SelectionOverlayController()
        controller.retainCycle = controller
        controller.scContent = content
        controller.completion = completion
        controller.present()
    }

    private func present() {
        for screen in NSScreen.screens {
            let win = makeOverlayWindow(for: screen)
            let view = SelectionView(screen: screen) { [weak self] selectedRect in
                self?.handleSelection(selectedRect)
            }
            win.contentView = view
            win.makeKeyAndOrderFront(nil)
            overlayWindows.append(win)
        }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
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
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return win
    }

    private func handleSelection(_ rect: CGRect?) {
        dismiss()
        guard let rect else { finish(nil); return }
        captureRect(rect)
    }

    private func dismiss() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func finish(_ image: NSImage?) {
        let cb = completion
        completion = nil
        retainCycle = nil
        scContent = nil
        cb?(image)
    }

    // MARK: - Capture via SCK

    private func captureRect(_ rect: CGRect) {
        guard let content = scContent else { finish(nil); return }

        guard let display = content.displays.first(where: { d in
            guard let ns = d.nsScreen else { return false }
            return ns.frame.contains(rect.origin)
        }) ?? content.displays.first,
              let ns = display.nsScreen else {
            finish(nil); return
        }

        // Use the display's native pixel ratio for maximum resolution.
        // SCStreamConfiguration.width/height are in pixels; sourceRect is in points.
        let scale = CGFloat(display.width) / ns.frame.width  // true pixel:point ratio
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width  = max(1, Int((rect.width  * scale).rounded()))
        cfg.height = max(1, Int((rect.height * scale).rounded()))
        cfg.sourceRect = CGRect(
            x: rect.origin.x - ns.frame.origin.x,
            y: ns.frame.height - (rect.origin.y - ns.frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )
        cfg.scalesToFit = false
        cfg.showsCursor = false

        slog("captureRect pixels=\(cfg.width)x\(cfg.height) scale=\(scale) sourceRect=\(cfg.sourceRect)")
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { [weak self] cgImage, error in
            DispatchQueue.main.async {
                if let cgImage {
                    // size in points so AppKit displays at correct logical size
                    self?.finish(NSImage(cgImage: cgImage, size: rect.size))
                } else {
                    slog("selection capture error: \(error?.localizedDescription ?? "nil")")
                    self?.finish(nil)
                }
            }
        }
    }
}

// MARK: - Selection rubber-band view

private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onSelect: (CGRect?) -> Void
    private var startPoint: CGPoint?
    private var currentRect: CGRect?

    init(screen: NSScreen, onSelect: @escaping (CGRect?) -> Void) {
        self.screen = screen
        self.onSelect = onSelect
        super.init(frame: screen.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override var isFlipped: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelect(nil) }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(start.x, cur.x), y: min(start.y, cur.y),
            width: abs(cur.x - start.x), height: abs(cur.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 4, rect.height > 4 else {
            onSelect(nil); return
        }
        let global = CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: screen.frame.origin.y + rect.origin.y,
            width: rect.width, height: rect.height
        )
        onSelect(global)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = currentRect else { return }
        NSGraphicsContext.current?.cgContext.clear(rect)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1.5
        path.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .backgroundColor: NSColor.black.withAlphaComponent(0.55)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: min(rect.maxX - sz.width - 4, bounds.maxX - sz.width - 4),
                             y: max(rect.minY + 4, 4)))
    }
}
