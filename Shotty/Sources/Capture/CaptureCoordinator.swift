import AppKit
import ScreenCaptureKit

final class CaptureCoordinator: NSObject, NSWindowDelegate {
    let mode: CaptureMode
    let onDone: () -> Void
    private var editorWindow: NSWindow?

    init(mode: CaptureMode, onDone: @escaping () -> Void) {
        self.mode = mode
        self.onDone = onDone
    }

    // MARK: - Entry point

    func start() {
        slog("start mode=\(mode)")
        // Single SCShareableContent call — triggers consent sheet on first use.
        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = error as? NSError {
                    slog("SCK error \(error.domain) \(error.code): \(error.localizedDescription)")
                    self.showPermissionAlert(error: error)
                    return
                }
                guard let content else { self.onDone(); return }
                slog("SCK ok: \(content.displays.count) displays, \(content.windows.count) windows")
                switch self.mode {
                case .fullScreen: self.captureFullScreen(content: content)
                case .window:     self.pickWindow(content: content)
                case .selection:  self.captureSelection(content: content)
                }
            }
        }
    }

    // MARK: - Full Screen

    private func captureFullScreen(content: SCShareableContent) {
        guard let display = content.displays.first else { onDone(); return }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        // display.width/height are already in native pixels — use them directly.
        cfg.width  = display.width
        cfg.height = display.height
        cfg.showsCursor = false

        // Hide our own overlay before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            slog("captureFullScreen \(cfg.width)x\(cfg.height)")
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { [weak self] cgImage, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let cgImage {
                        let size = display.nsScreen?.frame.size
                                 ?? CGSize(width: display.width, height: display.height)
                        self.openEditor(image: NSImage(cgImage: cgImage, size: size))
                    } else {
                        slog("fullScreen capture error: \(error?.localizedDescription ?? "nil")")
                        self.onDone()
                    }
                }
            }
        }
    }

    // MARK: - Window picker

    private func pickWindow(content: SCShareableContent) {
        WindowPickerOverlayController.show(content: content) { [weak self] image in
            guard let self else { return }
            if let image { self.openEditor(image: image) } else { self.onDone() }
        }
    }

    // MARK: - Selection

    private func captureSelection(content: SCShareableContent) {
        SelectionOverlayController.show(content: content) { [weak self] image in
            guard let self else { return }
            if let image { self.openEditor(image: image) } else { self.onDone() }
        }
    }

    // MARK: - Editor

    private func openEditor(image: NSImage) {
        slog("openEditor image=\(image.size)")
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxW = screen.visibleFrame.width  * 0.92
        let maxH = screen.visibleFrame.height * 0.92 - 48

        var displaySize = image.size
        if displaySize.width > maxW || displaySize.height > maxH {
            let ratio = min(maxW / displaySize.width, maxH / displaySize.height)
            displaySize = CGSize(width: floor(displaySize.width * ratio),
                                height: floor(displaySize.height * ratio))
        }

        let editorVC = AnnotationEditorViewController(image: image, displaySize: displaySize) { }

        let window = NSWindow(
            contentRect: CGRect(origin: .zero,
                                size: CGSize(width: displaySize.width,
                                             height: displaySize.height + 48)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shotty — Annotate"
        window.contentViewController = editorVC
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        editorWindow = window
        slog("editor window shown")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        slog("editor closed")
        editorWindow = nil
        NSApp.setActivationPolicy(.accessory)
        onDone()
    }

    // MARK: - Permission alert

    private func showPermissionAlert(error: NSError) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        // Error -3801 = SCStreamErrorUserDeclined (consent sheet was declined or not yet shown)
        if error.code == -3801 {
            alert.informativeText = """
                Shotty needs Screen Recording permission.

                Please go to:
                System Settings → Privacy & Security → Screen Recording

                Toggle Shotty OFF then back ON, then try again.
                (This resets the consent so the allow prompt appears.)
                """
        } else {
            alert.informativeText = """
                Shotty needs Screen Recording access (\(error.code)).

                Enable it in:
                System Settings → Privacy & Security → Screen Recording → Shotty ✓
                """
        }
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        NSApp.setActivationPolicy(.accessory)
        onDone()
    }
}

// MARK: - SCDisplay → NSScreen

extension SCDisplay {
    var nsScreen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == self.displayID
        }
    }
}
