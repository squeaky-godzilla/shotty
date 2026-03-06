import AppKit

class AnnotationCanvasView: NSView {
    var model: AnnotationModel
    var baseImage: NSImage

    private var activeTextField: NSTextField?
    private var activeTextAnnotationID: UUID?

    // Arrow tool state: first click sets origin, mouse move previews, second click commits
    private var arrowOrigin: CGPoint?
    private var arrowPreviewTip: CGPoint?

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
            str.draw(at: CGPoint(x: sticker.center.x - sz.width / 2,
                                 y: sticker.center.y - sz.height / 2))
        }

        // 6. Committed arrows
        for arrow in model.arrows {
            drawArrow(from: arrow.from, to: arrow.to,
                      color: arrow.color, lineWidth: arrow.lineWidth, in: ctx)
        }

        // 7. Arrow preview (while placing second point)
        if let origin = arrowOrigin, let tip = arrowPreviewTip {
            drawArrow(from: origin, to: tip,
                      color: model.currentColor, lineWidth: model.lineWidth, in: ctx)
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint,
                           color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 4 else { return }

        // Arrowhead size scales with line width but has a sensible minimum
        let headLen = max(lineWidth * 5, 16.0)
        let headAngle = CGFloat.pi / 6  // 30°

        let angle = atan2(dy, dx)
        let left  = CGPoint(x: to.x - headLen * cos(angle - headAngle),
                            y: to.y - headLen * sin(angle - headAngle))
        let right = CGPoint(x: to.x - headLen * cos(angle + headAngle),
                            y: to.y - headLen * sin(angle + headAngle))

        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Shaft — stop slightly before tip so it doesn't poke through the head
        let shaftTip = CGPoint(x: to.x - headLen * 0.6 * cos(angle),
                               y: to.y - headLen * 0.6 * sin(angle))
        ctx.move(to: from)
        ctx.addLine(to: shaftTip)
        ctx.strokePath()

        // Filled arrowhead
        ctx.move(to: to)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()

        ctx.restoreGState()
    }

    private func drawStroke(_ stroke: StrokeAnnotation, in ctx: CGContext) {
        guard stroke.points.count > 1 else { return }
        ctx.saveGState()
        if stroke.isEraser {
            // Erase by clearing pixels — blendMode .clear punches through to transparent,
            // then the view's opaque background (the base image) shows through correctly
            // when rendered into a bitmap context (renderToImage). On-screen we use
            // destinationOut which visually removes drawn content while keeping the image.
            ctx.setBlendMode(.clear)
            ctx.setStrokeColor(NSColor.white.cgColor)
        } else {
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.cgColor)
        }
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
        if let tf = activeTextField { commitTextAnnotation(tf) }

        switch model.currentTool {
        case .pen, .eraser:
            model.beginStroke(at: pt)
        case .text:
            startTextAnnotation(at: pt)
        case .sticker:
            model.addSticker(at: pt)
            needsDisplay = true
        case .arrow:
            if let origin = arrowOrigin {
                // Second click — commit the arrow
                model.addArrow(from: origin, to: pt)
                arrowOrigin = nil
                arrowPreviewTip = nil
            } else {
                // First click — set origin
                arrowOrigin = pt
                arrowPreviewTip = pt
            }
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard model.currentTool == .arrow, arrowOrigin != nil else { return }
        arrowPreviewTip = convert(event.locationInWindow, from: nil)
        needsDisplay = true
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
        tf.tag = 99
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

    func cancelTextAnnotation(_ tf: NSTextField) {
        // Remove the placeholder text entry without committing anything.
        if let annotationID = activeTextAnnotationID {
            model.cancelText(id: annotationID)
        }
        tf.removeFromSuperview()
        activeTextField = nil
        activeTextAnnotationID = nil
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Escape cancels a pending arrow origin
        if event.keyCode == 53 {
            if arrowOrigin != nil {
                arrowOrigin = nil
                arrowPreviewTip = nil
                needsDisplay = true
                return
            }
            super.keyDown(with: event); return
        }
        guard event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers {
        case "z":
            model.undoLast()
            needsDisplay = true
        case "c":
            nextResponder?.tryToPerform(#selector(NSText.copy(_:)), with: self)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Render to Image

    func renderToImage() -> NSImage {
        if let tf = activeTextField { commitTextAnnotation(tf) }

        let pixelSize = baseImage.size
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
            let img = NSImage(size: bounds.size)
            img.lockFocus(); draw(bounds); img.unlockFocus()
            return img
        }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = ctx
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
        case .arrow:   NSCursor.crosshair.set()
        }
        // Arrow tool needs mouseMoved events for live preview
        window?.acceptsMouseMovedEvents = (model.currentTool == .arrow)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

// MARK: - NSTextFieldDelegate

extension AnnotationCanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf.tag == 99 else { return }
        // Check if ended due to Escape (movement == cancel)
        if let movement = (obj.userInfo?["NSTextMovement"] as? Int),
           movement == NSTextMovement.cancel.rawValue {
            cancelTextAnnotation(tf)
        } else {
            commitTextAnnotation(tf)
        }
    }
}
