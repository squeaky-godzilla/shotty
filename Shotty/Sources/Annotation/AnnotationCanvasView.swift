import AppKit

class AnnotationCanvasView: NSView {
    var model: AnnotationModel
    var baseImage: NSImage

    private var activeTextField: NSTextField?
    private var activeTextAnnotationID: UUID?

    // Arrow tool state: first click sets origin, mouse move previews, second click commits
    private var arrowOrigin: CGPoint?
    private var arrowPreviewTip: CGPoint?
    
    // Drag state for moving selected annotations
    private var isDraggingAnnotation = false
    private var dragStartPoint: CGPoint?

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
                      color: model.currentColor, lineWidth: model.arrowSize, in: ctx)
        }
        
        // 8. Selection highlight
        if let selected = model.selectedAnnotation {
            drawSelectionHighlight(for: selected, in: ctx)
        }
    }
    
    private func drawSelectionHighlight(for selection: SelectedAnnotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        
        switch selection {
        case .stroke(let id):
            guard let stroke = model.strokes.first(where: { $0.id == id }),
                  !stroke.points.isEmpty else { break }
            // Draw bounding box around stroke
            let minX = stroke.points.map(\.x).min() ?? 0
            let maxX = stroke.points.map(\.x).max() ?? 0
            let minY = stroke.points.map(\.y).min() ?? 0
            let maxY = stroke.points.map(\.y).max() ?? 0
            let padding: CGFloat = 8
            ctx.stroke(CGRect(x: minX - padding, y: minY - padding,
                            width: maxX - minX + padding * 2, height: maxY - minY + padding * 2))
            
        case .arrow(let id):
            guard let arrow = model.arrows.first(where: { $0.id == id }) else { break }
            let minX = min(arrow.from.x, arrow.to.x)
            let maxX = max(arrow.from.x, arrow.to.x)
            let minY = min(arrow.from.y, arrow.to.y)
            let maxY = max(arrow.from.y, arrow.to.y)
            let padding: CGFloat = 8
            ctx.stroke(CGRect(x: minX - padding, y: minY - padding,
                            width: maxX - minX + padding * 2, height: maxY - minY + padding * 2))
            
        case .text(let id):
            guard let text = model.texts.first(where: { $0.id == id }) else { break }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: text.fontSize, weight: .bold)
            ]
            let str = NSAttributedString(string: text.text, attributes: attrs)
            let size = str.size()
            let padding: CGFloat = 4
            ctx.stroke(CGRect(x: text.origin.x - padding, y: text.origin.y - padding,
                            width: size.width + padding * 2, height: size.height + padding * 2))
            
        case .sticker(let id):
            guard let sticker = model.stickers.first(where: { $0.id == id }) else { break }
            let radius = sticker.size / 2 + 8
            ctx.strokeEllipse(in: CGRect(x: sticker.center.x - radius, y: sticker.center.y - radius,
                                        width: radius * 2, height: radius * 2))
        }
        
        ctx.restoreGState()
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
        case .pen:
            model.beginStroke(at: pt)
        case .text:
            startTextAnnotation(at: pt)
        case .sticker:
            model.addSticker(at: pt)
            needsDisplay = true
        case .arrow:
            // Click to start arrow
            arrowOrigin = pt
            arrowPreviewTip = pt
            needsDisplay = true
        case .select:
            // Try to select an annotation at the clicked point
            if model.selectAnnotation(at: pt) {
                isDraggingAnnotation = true
                dragStartPoint = pt
                
                // Double-click on text to edit
                if event.clickCount == 2, case .text(let id) = model.selectedAnnotation {
                    editTextAnnotation(id: id)
                    isDraggingAnnotation = false
                    dragStartPoint = nil
                }
                
                needsDisplay = true
            } else {
                model.selectedAnnotation = nil
                isDraggingAnnotation = false
                dragStartPoint = nil
                needsDisplay = true
            }
        case .eraser:
            break // Eraser removed
        }
    }
    
    private func editTextAnnotation(id: UUID) {
        guard let idx = model.texts.firstIndex(where: { $0.id == id }) else { return }
        let textAnnotation = model.texts[idx]
        
        // Remove from committed texts temporarily
        model.texts[idx].isEditing = true
        
        let tf = NSTextField(frame: CGRect(x: textAnnotation.origin.x, 
                                          y: textAnnotation.origin.y, 
                                          width: 250, height: 30))
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.textColor = textAnnotation.color
        tf.font = NSFont.systemFont(ofSize: textAnnotation.fontSize, weight: .bold)
        tf.stringValue = textAnnotation.text
        tf.focusRingType = .none
        tf.delegate = self
        tf.tag = 99
        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
        activeTextAnnotationID = id
        needsDisplay = true
    }



    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        
        if model.currentTool == .pen {
            model.continueStroke(to: pt)
            needsDisplay = true
        } else if model.currentTool == .arrow && arrowOrigin != nil {
            // Update arrow preview while dragging
            arrowPreviewTip = pt
            needsDisplay = true
        } else if model.currentTool == .select && isDraggingAnnotation, let start = dragStartPoint {
            let dx = pt.x - start.x
            let dy = pt.y - start.y
            model.moveSelectedAnnotation(dx: dx, dy: dy)
            dragStartPoint = pt
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        
        if model.currentTool == .pen {
            model.endStroke()
            needsDisplay = true
        } else if model.currentTool == .arrow, let origin = arrowOrigin {
            // Release to finish arrow
            model.addArrow(from: origin, to: pt)
            arrowOrigin = nil
            arrowPreviewTip = nil
            needsDisplay = true
        } else if model.currentTool == .select {
            isDraggingAnnotation = false
            dragStartPoint = nil
        }
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
        // Delete/Backspace key (keyCode 51 = Delete, 117 = Forward Delete)
        if event.keyCode == 51 || event.keyCode == 117 {
            if model.selectedAnnotation != nil {
                model.deleteSelectedAnnotation()
                needsDisplay = true
                return
            }
        }
        
        // Escape cancels a pending arrow origin or deselects
        if event.keyCode == 53 {
            if arrowOrigin != nil {
                arrowOrigin = nil
                arrowPreviewTip = nil
                needsDisplay = true
                return
            }
            if model.selectedAnnotation != nil {
                model.selectedAnnotation = nil
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
        case .select:  NSCursor.arrow.set()
        case .pen:     NSCursor.crosshair.set()
        case .text:    NSCursor.iBeam.set()
        case .sticker: NSCursor.pointingHand.set()
        case .arrow:   NSCursor.crosshair.set()
        case .eraser:  NSCursor.arrow.set() // Fallback (should not be used)
        }
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
