import AppKit
import Carbon.HIToolbox

// Simple file logger — writes to /tmp/shotty.log
func slog(_ msg: String) {
    let line = "\(msg)\n"
    let path = "/tmp/shotty.log"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path),
       let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?
    var captureCoordinator: CaptureCoordinator?
    var hotKeyEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? "=== Shotty launched ===\n".write(toFile: "/tmp/shotty.log", atomically: true, encoding: .utf8)
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        registerGlobalHotKey()
        // Ignore the spurious Carbon hotkey fire on registration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hotKeyEnabled = true
        }
        // Note: we do NOT call SCShareableContent at launch.
        // The system picker sheet is shown once on the first capture attempt,
        // after which the grant is stored and subsequent captures are silent.
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "camera",
                                            accessibilityDescription: "Shotty")
        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Window",      action: #selector(captureWindow),     keyEquivalent: "")
        menu.addItem(withTitle: "Capture Selection",   action: #selector(captureSelection),  keyEquivalent: "")
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Shotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        // Set target only on capture items, not the quit item (already added above).
        for item in menu.items where item != quitItem && !item.isSeparatorItem {
            item.target = self
        }
        statusItem?.menu = menu
    }

    // MARK: - Global Hotkey (Ctrl+Shift+S)

    func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let d = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                guard d.hotKeyEnabled else { return noErr }
                DispatchQueue.main.async { d.captureSelection() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), nil
        )
        let hotKeyID = EventHotKeyID(signature: 0x53484F54, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | shiftKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Actions

    @objc func captureFullScreen() { showCaptureUI(mode: .fullScreen) }
    @objc func captureWindow()     { showCaptureUI(mode: .window) }
    @objc func captureSelection()  { showCaptureUI(mode: .selection) }

    private func showCaptureUI(mode: CaptureMode) {
        slog("showCaptureUI mode=\(mode)")
        captureCoordinator = CaptureCoordinator(mode: mode) { [weak self] in
            self?.captureCoordinator = nil
        }
        captureCoordinator?.start()
    }
}
