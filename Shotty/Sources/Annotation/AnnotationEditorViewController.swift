import AppKit
import UniformTypeIdentifiers

/// The main editor: toolbar on top, annotation canvas (in a scroll view) below.
class AnnotationEditorViewController: NSViewController {
    private let image: NSImage
    private let displaySize: CGSize
    private let onClose: () -> Void
    private let model = AnnotationModel()
    private var canvasView: AnnotationCanvasView!
    private var emojiBtn: NSButton!

    init(image: NSImage, displaySize: CGSize, onClose: @escaping () -> Void) {
        self.image = image
        self.displaySize = displaySize
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View Loading

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero,
                                            size: CGSize(width: displaySize.width,
                                                         height: displaySize.height + 48)))

        // Toolbar
        let toolbar = buildToolbar()
        toolbar.frame = NSRect(x: 0, y: displaySize.height, width: displaySize.width, height: 48)
        toolbar.autoresizingMask = [.width, .minYMargin]

        // Canvas — draws at the full original image resolution
        canvasView = AnnotationCanvasView(image: image, model: model)
        canvasView.frame = CGRect(origin: .zero, size: image.size)

        // Scroll view to contain the canvas
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: displaySize))
        scrollView.documentView = canvasView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scrollView.autoresizingMask = [.width, .height]

        container.addSubview(scrollView)
        container.addSubview(toolbar)

        view = container
    }

    // MARK: - Toolbar Builder

    private func buildToolbar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .sidebar
        bar.state = .active

        func iconBtn(_ sfSymbol: String, _ tip: String, _ sel: Selector) -> NSButton {
            let b = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            b.image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: tip)
            b.imageScaling = .scaleProportionallyUpOrDown
            b.isBordered = false
            b.toolTip = tip
            b.target = self
            b.action = sel
            return b
        }

        let penBtn     = iconBtn("pencil",               "Pen",              #selector(selectPen))
        let eraserBtn  = iconBtn("eraser",               "Eraser",           #selector(selectEraser))
        let textBtn    = iconBtn("textformat",            "Text",             #selector(selectText))
        let stickerBtn = iconBtn("face.smiling",          "Sticker",          #selector(selectSticker))
        let undoBtn    = iconBtn("arrow.uturn.backward",  "Undo (⌘Z)",        #selector(undoAction))
        let copyBtn    = iconBtn("doc.on.clipboard",      "Copy to Clipboard",#selector(copyToClipboard))
        let saveBtn    = iconBtn("square.and.arrow.down", "Save PNG",         #selector(saveAsPNG))

        // Colour well
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        colorWell.color = model.currentColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))

        // Stroke width label + stepper
        let widthLabel   = NSTextField(labelWithString: "Size:")
        let widthStepper = NSStepper(frame: NSRect(x: 0, y: 0, width: 19, height: 27))
        widthStepper.minValue = 1
        widthStepper.maxValue = 40
        widthStepper.integerValue = Int(model.lineWidth)
        widthStepper.target = self
        widthStepper.action = #selector(lineWidthChanged(_:))

        // Emoji button (shows selected emoji, opens picker)
        emojiBtn = NSButton(title: model.selectedEmoji,
                            target: self,
                            action: #selector(showEmojiPicker(_:)))
        emojiBtn.font = NSFont.systemFont(ofSize: 20)
        emojiBtn.isBordered = false
        emojiBtn.toolTip = "Choose sticker"

        // Divider
        func sep() -> NSView {
            let b = NSBox()
            b.boxType = .separator
            return b
        }

        let leftItems: [NSView] = [penBtn, eraserBtn, textBtn, stickerBtn, sep(), colorWell, widthLabel, widthStepper, sep(), emojiBtn]
        let rightItems: [NSView] = [undoBtn, sep(), copyBtn, saveBtn]

        let leftStack  = NSStackView(views: leftItems)
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 6
        leftStack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)

        let rightStack = NSStackView(views: rightItems)
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 6
        rightStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 10)

        leftStack.translatesAutoresizingMaskIntoConstraints  = false
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(leftStack)
        bar.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            leftStack.topAnchor.constraint(equalTo: bar.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            rightStack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: bar.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        return bar
    }

    // MARK: - Tool selection

    @objc private func selectPen()     { model.currentTool = .pen;     canvasView.updateCursor() }
    @objc private func selectEraser()  { model.currentTool = .eraser;  canvasView.updateCursor() }
    @objc private func selectText()    { model.currentTool = .text;    canvasView.updateCursor() }
    @objc private func selectSticker() { model.currentTool = .sticker; canvasView.updateCursor() }

    // MARK: - Colour

    @objc private func colorChanged(_ sender: NSColorWell) {
        model.currentColor = sender.color
    }

    // MARK: - Stroke width

    @objc private func lineWidthChanged(_ sender: NSStepper) {
        model.lineWidth = CGFloat(sender.integerValue)
    }

    // MARK: - Emoji Picker

    @objc private func showEmojiPicker(_ sender: NSButton) {
        let picker = EmojiPickerViewController(selected: model.selectedEmoji) { [weak self] emoji in
            guard let self = self else { return }
            self.model.selectedEmoji = emoji
            self.model.currentTool = .sticker
            self.emojiBtn.title = emoji
        }
        present(picker, asPopoverRelativeTo: sender.bounds, of: sender,
                preferredEdge: .minY, behavior: .transient)
    }

    // MARK: - Undo

    @objc private func undoAction() {
        model.undoLast()
        canvasView.needsDisplay = true
    }

    // MARK: - Copy to Clipboard

    @objc private func copyToClipboard() {
        let rendered = canvasView.renderToImage()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([rendered])
        showFlash("Copied to clipboard!")
    }

    // Respond to Cmd+C via the responder chain (Edit menu or keyboard shortcut).
    @objc func copy(_ sender: Any?) {
        copyToClipboard()
    }

    // MARK: - Save PNG

    @objc private func saveAsPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "shotty-\(Date.shottyTimestamp).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let rendered = canvasView.renderToImage()
        guard let tiff   = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        showFlash("Saved!")
    }

    // MARK: - Flash HUD

    private func showFlash(_ message: String) {
        let label = NSTextField(labelWithString: "  \(message)  ")
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        label.drawsBackground = true
        label.isBezeled = false
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.heightAnchor.constraint(equalToConstant: 38),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                label.animator().alphaValue = 0
            } completionHandler: {
                label.removeFromSuperview()
            }
        }
    }
}

// MARK: - Helpers

extension Date {
    static var shottyTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
