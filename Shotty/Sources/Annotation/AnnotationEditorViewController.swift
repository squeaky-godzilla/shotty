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
    private var colorPopup: NSPopUpButton!
    private var thicknessControl: NSSegmentedControl!
    private var watermarkCheckbox: NSButton!
    private var shouldAddWatermark = false

    // Preset colours — (display name, NSColor)
    private static let presetColors: [(String, NSColor)] = [
        ("Red",     .systemRed),
        ("Orange",  .systemOrange),
        ("Yellow",  .systemYellow),
        ("Green",   .systemGreen),
        ("Blue",    .systemBlue),
        ("Purple",  .systemPurple),
        ("Pink",    .systemPink),
        ("White",   .white),
        ("Black",   .black),
    ]

    init(image: NSImage, displaySize: CGSize, onClose: @escaping () -> Void) {
        self.image = image
        self.displaySize = displaySize
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View Loading

    override func loadView() {
        let toolbarHeight: CGFloat = 96
        // Use a flexible container that can accommodate minimum window size
        let container = NSView(frame: NSRect(origin: .zero,
                                            size: CGSize(width: max(displaySize.width, 640),
                                                         height: max(displaySize.height, 400 - toolbarHeight) + toolbarHeight)))

        let toolbar = buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        canvasView = AnnotationCanvasView(image: image, model: model)
        canvasView.frame = CGRect(origin: .zero, size: image.size)

        // Create a scroll view with centering clip view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvasView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scrollView.drawsBackground = true

        container.addSubview(scrollView)
        container.addSubview(toolbar)
        
        // Use Auto Layout for flexible sizing
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        view = container
    }

    // MARK: - Toolbar Builder

    private func buildToolbar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .sidebar
        bar.state = .active

        func iconBtn(_ sfSymbol: String, _ tip: String, _ sel: Selector) -> NSButton {
            let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            let b = NSButton(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
            b.image = NSImage(systemSymbolName: sfSymbol,
                              accessibilityDescription: tip)?
                      .withSymbolConfiguration(cfg)
            b.imageScaling = .scaleProportionallyUpOrDown
            b.isBordered = false
            b.toolTip = tip
            b.target = self
            b.action = sel
            return b
        }

        let selectBtn  = iconBtn("hand.point.up.left",    "Select",            #selector(selectSelect))
        let penBtn     = iconBtn("pencil",               "Pen",               #selector(selectPen))
        let textBtn    = iconBtn("textformat",            "Text",              #selector(selectText))
        let stickerBtn = iconBtn("face.smiling",          "Sticker",           #selector(selectSticker))
        let arrowBtn   = iconBtn("arrow.up.right",        "Arrow",             #selector(selectArrow))
        let undoBtn    = iconBtn("arrow.uturn.backward",  "Undo (⌘Z)",         #selector(undoAction))
        let copyBtn    = iconBtn("doc.on.clipboard",      "Copy to Clipboard", #selector(copyToClipboard))
        let saveBtn    = iconBtn("square.and.arrow.down", "Save PNG",          #selector(saveAsPNG))

        // Colour preset popup
        colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
        colorPopup.target = self
        colorPopup.action = #selector(colorPresetChanged(_:))
        for (name, color) in Self.presetColors {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.image = colorSwatch(color)
            colorPopup.menu?.addItem(item)
        }
        colorPopup.selectItem(at: 0) // default: Red
        model.currentColor = Self.presetColors[0].1

        // Stroke width segmented control
        let widthLabel = NSTextField(labelWithString: "Thickness:")
        thicknessControl = NSSegmentedControl(labels: ["Thin", "Medium", "Thick"], 
                                                trackingMode: .selectOne, 
                                                target: self, 
                                                action: #selector(thicknessChanged(_:)))
        thicknessControl.selectedSegment = 1 // default: Medium
        model.lineWidth = 4.0 // Medium thickness
        model.arrowSize = 4.0 // Medium thickness

        // Emoji button
        emojiBtn = NSButton(title: model.selectedEmoji,
                            target: self,
                            action: #selector(showEmojiPicker(_:)))
        emojiBtn.font = NSFont.systemFont(ofSize: 26)
        emojiBtn.isBordered = false
        emojiBtn.toolTip = "Choose sticker"
        
        // Watermark checkbox
        watermarkCheckbox = NSButton(checkboxWithTitle: "Add watermark", target: self, action: #selector(watermarkToggled(_:)))
        watermarkCheckbox.toolTip = "Add 'Made with Shotty' link at bottom right"
        watermarkCheckbox.state = .off

        func sep() -> NSView {
            let b = NSBox(); b.boxType = .separator; return b
        }

        let leftItems: [NSView]  = [selectBtn, penBtn, textBtn, arrowBtn, stickerBtn,
                                    sep(), colorPopup, widthLabel, thicknessControl,
                                    sep(), emojiBtn]
        let rightItems: [NSView] = [watermarkCheckbox, sep(), undoBtn, sep(), copyBtn, saveBtn]

        let leftStack  = NSStackView(views: leftItems)
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 8
        leftStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 8)

        let rightStack = NSStackView(views: rightItems)
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 8
        rightStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 12)

        leftStack.translatesAutoresizingMaskIntoConstraints  = false
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)
        leftStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        bar.addSubview(leftStack)
        bar.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            leftStack.topAnchor.constraint(equalTo: bar.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
            rightStack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: bar.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        return bar
    }

    // Build a 16×16 filled circle swatch image for a colour menu item.
    private func colorSwatch(_ color: NSColor) -> NSImage {
        let size = CGSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
    }

    // MARK: - Tool selection

    @objc private func selectSelect() {
        model.currentTool = .select
        canvasView.updateCursor()
    }
    
    @objc private func selectPen() {
        model.currentTool = .pen
        syncThicknessControl(for: model.lineWidth)
        canvasView.updateCursor()
    }
    
    @objc private func selectText() {
        model.currentTool = .text
        canvasView.updateCursor()
    }
    
    @objc private func selectSticker() {
        model.currentTool = .sticker
        canvasView.updateCursor()
    }
    
    @objc private func selectArrow() {
        model.currentTool = .arrow
        syncThicknessControl(for: model.arrowSize)
        canvasView.updateCursor()
    }
    
    private func syncThicknessControl(for width: CGFloat) {
        // Sync the segmented control to match current width
        if width <= 2.5 {
            thicknessControl.selectedSegment = 0 // Thin
        } else if width <= 6.0 {
            thicknessControl.selectedSegment = 1 // Medium
        } else {
            thicknessControl.selectedSegment = 2 // Thick
        }
    }

    // MARK: - Colour preset

    @objc private func colorPresetChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.presetColors.count else { return }
        model.currentColor = Self.presetColors[idx].1
        
        // If in select mode and an annotation is selected, update its color
        if model.currentTool == .select {
            model.updateSelectedAnnotationColor(model.currentColor)
            canvasView.needsDisplay = true
        }
    }

    // MARK: - Stroke width

    @objc private func thicknessChanged(_ sender: NSSegmentedControl) {
        let thickness: CGFloat
        switch sender.selectedSegment {
        case 0: thickness = 2.0  // Thin
        case 1: thickness = 4.0  // Medium
        case 2: thickness = 8.0  // Thick
        default: thickness = 4.0
        }
        
        // Apply to the appropriate property based on current tool
        switch model.currentTool {
        case .pen:
            model.lineWidth = thickness
        case .arrow:
            model.arrowSize = thickness
        case .select:
            // Update selected annotation's thickness
            model.updateSelectedAnnotationThickness(thickness)
            canvasView.needsDisplay = true
        case .text, .sticker, .eraser:
            break // Thickness doesn't apply to these tools
        }
    }

    // MARK: - Emoji Picker

    @objc private func showEmojiPicker(_ sender: NSButton) {
        let picker = EmojiPickerViewController(selected: model.selectedEmoji) { [weak self] emoji in
            guard let self else { return }
            self.model.selectedEmoji = emoji
            self.model.currentTool = .sticker
            self.emojiBtn.title = emoji
        }
        present(picker, asPopoverRelativeTo: sender.bounds, of: sender,
                preferredEdge: .minY, behavior: .transient)
    }

    // MARK: - Watermark
    
    @objc private func watermarkToggled(_ sender: NSButton) {
        shouldAddWatermark = (sender.state == .on)
        canvasView.shouldDrawWatermark = shouldAddWatermark
        canvasView.needsDisplay = true
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

    @objc func copy(_ sender: Any?) { copyToClipboard() }

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
            } completionHandler: { label.removeFromSuperview() }
        }
    }
}

// MARK: - Centering Clip View

/// A clip view that centers the document view when it's smaller than the visible area
class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView = documentView else { return rect }
        
        let documentFrame = documentView.frame
        
        // Center horizontally if document is narrower than clip view
        if documentFrame.width < rect.width {
            rect.origin.x = -(rect.width - documentFrame.width) / 2
        }
        
        // Center vertically if document is shorter than clip view
        if documentFrame.height < rect.height {
            rect.origin.y = -(rect.height - documentFrame.height) / 2
        }
        
        return rect
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
