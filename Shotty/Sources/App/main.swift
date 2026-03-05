import AppKit

// Entry point — pure AppKit, no SwiftUI needed.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
