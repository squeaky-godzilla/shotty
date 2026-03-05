import AppKit

/// NSView subclass that renders the screenshot + all annotations and handles mouse/keyboard input.
class AnnotationCanvasView: NSView {
    var model: AnnotationModel
    var baseImage: NSImage

    // Text editing state
    private var activeTextField: NSTextField?
    private var activeTextAnnotationID: UUID?

    init(image: NSImage, model: AnnotationModel) {
        self.baseImage = image
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: image.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Base image
        baseImage.draw(in: bounds)

        // 2. Committed strokes
        for stroke in model.strokes {
            drawStroke(stroke, in: ctx)
        }

        // 3. Active stroke
        if let active = model.activeStroke {
            drawStroke(active, in: ctx)
        }

        // 4. Text annotations
        for text in model.texts where !text.isEditing {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: text.color,
                .font: NSFont.systemFont(ofSize: text.fontSize, weight: .bold)
            ]
            NSAttributedString(string: text.text, attributes: attrs).draw(at: text.origin)
        }

        // 5. Stickers
        for sticker in model.stickers {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: sticker.size)
            ]
            let str = NSAttributedString(string: sticker.emoji, attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: sticker.center.x - sz.width / 2, y: sticker.center.y - sz.height / 2))
        }
    }

    private func drawStroke(_ stroke: StrokeAnnotation, in ctx: CGContext) {
        guard stroke.points.count > 1 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: stroke.points[0])
        for pt in stroke.points.dropFirst() {
            ctx.addLine(to: pt)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        // Dismiss active text field on click outside
        if let tf = activeTextField {
            commitTextAnnotation(tf)
        }

        switch model.currentTool {
        case .pen:
            model.beginStroke(at: pt)
        case .eraser:
            model.beginStroke(at: pt)
        case .text:
            startTextAnnotation(at: pt)
        case .sticker:
            model.addSticker(at: pt)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard model.currentTool == .pen || model.currentTool == .eraser else { return }
        model.continueStroke(to: pt)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard model.currentTool == .pen || model.currentTool == .eraser else { return }
        model.endStroke()
        needsDisplay = true
    }

    // MARK: - Text Annotation

    private func startTextAnnotation(at point: CGPoint) {
        let annotationID = model.addText(at: point)
        activeTextAnnotationID = annotationID

        let tf = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 250, height: 30))
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.textColor = model.currentColor
        tf.font = NSFont.systemFont(ofSize: model.fontSize, weight: .bold)
        tf.placeholderString = "Type here…"
        tf.focusRingType = .none
        tf.delegate = self
        tf.tag = 99 // sentinel
        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
    }

    func commitTextAnnotation(_ tf: NSTextField) {
        guard let annotationID = activeTextAnnotationID else { return }
        model.finishTextEditing(id: annotationID, text: tf.stringValue)
        tf.removeFromSuperview()
        activeTextField = nil
        activeTextAnnotationID = nil
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers {
        case "z":
            model.undoLast()
            needsDisplay = true
        case "c":
            // Forward up the responder chain so AnnotationEditorViewController.copy(_:) handles it.
            nextResponder?.tryToPerform(#selector(NSText.copy(_:)), with: self)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Render to Image

    func renderToImage() -> NSImage {
        if let tf = activeTextField { commitTextAnnotation(tf) }

        // Render at the full backing resolution of the base image, not just the
        // display size — this preserves the original capture quality.
        let pixelSize = baseImage.size  // baseImage.size is already in pixels (set from CGImage)
        let scale = pixelSize.width / bounds.size.width

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            // Fallback
            let img = NSImage(size: bounds.size)
            img.lockFocus(); draw(bounds); img.unlockFocus()
            return img
        }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = ctx
        // Scale up so draw() coordinates (points) map to full pixel resolution
        ctx?.cgContext.scaleBy(x: scale, y: scale)
        draw(bounds)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: pixelSize)
        result.addRepresentation(bitmapRep)
        return result
    }

    // MARK: - Cursor

    func updateCursor() {
        switch model.currentTool {
        case .pen:     NSCursor.crosshair.set()
        case .eraser:  NSCursor.disappearingItem.set()
        case .text:    NSCursor.iBeam.set()
        case .sticker: NSCursor.pointingHand.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

extension AnnotationCanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf.tag == 99 else { return }
        commitTextAnnotation(tf)
    }
}
