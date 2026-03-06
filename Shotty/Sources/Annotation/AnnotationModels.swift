import AppKit

// MARK: - Tool

enum AnnotationTool: Equatable {
    case pen
    case text
    case sticker
    case eraser
    case arrow
    case select  // New tool for selecting and editing annotations
}

// MARK: - Selection

enum SelectedAnnotation: Equatable {
    case stroke(UUID)
    case text(UUID)
    case sticker(UUID)
    case arrow(UUID)
}

// MARK: - Annotation items

struct StrokeAnnotation {
    let id = UUID()
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    /// When tool is eraser we blend with .clear
    var isEraser: Bool = false
}

struct TextAnnotation {
    let id = UUID()
    var text: String
    var origin: CGPoint   // bottom-left in view (non-flipped) coords
    var color: NSColor
    var fontSize: CGFloat
    var isEditing: Bool = false
}

struct StickerAnnotation {
    let id = UUID()
    var emoji: String
    var center: CGPoint
    var size: CGFloat
}

struct ArrowAnnotation {
    let id = UUID()
    var from: CGPoint
    var to: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
}

// MARK: - Undo action stack entry

private enum UndoAction {
    case stroke
    case text
    case sticker
    case arrow
}

// MARK: - Canvas model

class AnnotationModel {
    var strokes:  [StrokeAnnotation]  = []
    var texts:    [TextAnnotation]    = []
    var stickers: [StickerAnnotation] = []
    var arrows:   [ArrowAnnotation]   = []

    var currentTool:   AnnotationTool = .pen
    var currentColor:  NSColor        = .systemRed
    var lineWidth:     CGFloat        = 4.0  // Default to medium (matches UI)
    var arrowSize:     CGFloat        = 4.0  // Arrow thickness (thin/medium/thick: 2/4/8)
    var fontSize:      CGFloat        = 18.0
    var selectedEmoji: String         = "❤️"

    var activeStroke: StrokeAnnotation?
    var selectedAnnotation: SelectedAnnotation?

    // Order stack for undo
    private var undoStack: [UndoAction] = []

    // MARK: Stroke

    func beginStroke(at point: CGPoint) {
        activeStroke = StrokeAnnotation(
            points: [point],
            color: currentTool == .eraser ? .clear : currentColor,
            lineWidth: lineWidth,
            isEraser: currentTool == .eraser
        )
    }

    func continueStroke(to point: CGPoint) {
        activeStroke?.points.append(point)
    }

    func endStroke() {
        if let stroke = activeStroke, stroke.points.count > 1 {
            strokes.append(stroke)
            undoStack.append(.stroke)
        }
        activeStroke = nil
    }

    // MARK: Text

    func addText(at point: CGPoint) -> UUID {
        let t = TextAnnotation(text: "", origin: point, color: currentColor,
                               fontSize: fontSize, isEditing: true)
        texts.append(t)
        // Don't push to undoStack yet — do it on commit
        return t.id
    }

    func finishTextEditing(id: UUID, text: String) {
        guard let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        if text.isEmpty {
            texts.remove(at: idx)
        } else {
            texts[idx].text = text
            texts[idx].isEditing = false
            undoStack.append(.text)
        }
    }

    func cancelText(id: UUID) {
        texts.removeAll { $0.id == id }
    }

    // MARK: Sticker

    func addSticker(at point: CGPoint) {
        let s = StickerAnnotation(emoji: selectedEmoji, center: point, size: 36)
        stickers.append(s)
        undoStack.append(.sticker)
    }

    // MARK: Arrow

    func addArrow(from: CGPoint, to: CGPoint) {
        let a = ArrowAnnotation(from: from, to: to, color: currentColor, lineWidth: arrowSize)
        arrows.append(a)
        undoStack.append(.arrow)
    }

    // MARK: Undo

    func undoLast() {
        guard let last = undoStack.last else { return }
        undoStack.removeLast()
        switch last {
        case .stroke:  if !strokes.isEmpty  { strokes.removeLast()  }
        case .text:    if !texts.isEmpty    { texts.removeLast()    }
        case .sticker: if !stickers.isEmpty { stickers.removeLast() }
        case .arrow:   if !arrows.isEmpty   { arrows.removeLast()   }
        }
    }
    
    // MARK: Selection and Editing
    
    func selectAnnotation(at point: CGPoint, tolerance: CGFloat = 20.0) -> Bool {
        // Check arrows first (lines are harder to hit)
        for arrow in arrows.reversed() {
            if isPoint(point, nearLine: arrow.from, to: arrow.to, tolerance: tolerance) {
                selectedAnnotation = .arrow(arrow.id)
                return true
            }
        }
        
        // Check strokes
        for stroke in strokes.reversed() {
            if stroke.points.contains(where: { distance(from: point, to: $0) < tolerance }) {
                selectedAnnotation = .stroke(stroke.id)
                return true
            }
        }
        
        // Check stickers
        for sticker in stickers.reversed() {
            if distance(from: point, to: sticker.center) < sticker.size / 2 + tolerance {
                selectedAnnotation = .sticker(sticker.id)
                return true
            }
        }
        
        // Check text
        for text in texts.reversed() {
            // Simple bounds check (could be improved with actual text bounds)
            let textSize = CGSize(width: 200, height: text.fontSize * 1.2)
            let textRect = CGRect(origin: text.origin, size: textSize)
            if textRect.contains(point) {
                selectedAnnotation = .text(text.id)
                return true
            }
        }
        
        selectedAnnotation = nil
        return false
    }
    
    func updateSelectedAnnotationThickness(_ thickness: CGFloat) {
        guard let selected = selectedAnnotation else { return }
        switch selected {
        case .stroke(let id):
            if let idx = strokes.firstIndex(where: { $0.id == id }) {
                strokes[idx].lineWidth = thickness
            }
        case .arrow(let id):
            if let idx = arrows.firstIndex(where: { $0.id == id }) {
                arrows[idx].lineWidth = thickness
            }
        case .text, .sticker:
            break // Thickness doesn't apply
        }
    }
    
    func updateSelectedAnnotationColor(_ color: NSColor) {
        guard let selected = selectedAnnotation else { return }
        switch selected {
        case .stroke(let id):
            if let idx = strokes.firstIndex(where: { $0.id == id }), !strokes[idx].isEraser {
                strokes[idx].color = color
            }
        case .arrow(let id):
            if let idx = arrows.firstIndex(where: { $0.id == id }) {
                arrows[idx].color = color
            }
        case .text(let id):
            if let idx = texts.firstIndex(where: { $0.id == id }) {
                texts[idx].color = color
            }
        case .sticker:
            break // Color doesn't apply to stickers
        }
    }
    
    func moveSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
        guard let selected = selectedAnnotation else { return }
        switch selected {
        case .stroke(let id):
            if let idx = strokes.firstIndex(where: { $0.id == id }) {
                strokes[idx].points = strokes[idx].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        case .arrow(let id):
            if let idx = arrows.firstIndex(where: { $0.id == id }) {
                arrows[idx].from = CGPoint(x: arrows[idx].from.x + dx, y: arrows[idx].from.y + dy)
                arrows[idx].to = CGPoint(x: arrows[idx].to.x + dx, y: arrows[idx].to.y + dy)
            }
        case .text(let id):
            if let idx = texts.firstIndex(where: { $0.id == id }) {
                texts[idx].origin = CGPoint(x: texts[idx].origin.x + dx, y: texts[idx].origin.y + dy)
            }
        case .sticker(let id):
            if let idx = stickers.firstIndex(where: { $0.id == id }) {
                stickers[idx].center = CGPoint(x: stickers[idx].center.x + dx, y: stickers[idx].center.y + dy)
            }
        }
    }
    
    func deleteSelectedAnnotation() {
        guard let selected = selectedAnnotation else { return }
        switch selected {
        case .stroke(let id):
            strokes.removeAll { $0.id == id }
        case .arrow(let id):
            arrows.removeAll { $0.id == id }
        case .text(let id):
            texts.removeAll { $0.id == id }
        case .sticker(let id):
            stickers.removeAll { $0.id == id }
        }
        selectedAnnotation = nil
    }
    
    // MARK: Helper functions
    
    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func isPoint(_ point: CGPoint, nearLine from: CGPoint, to: CGPoint, tolerance: CGFloat) -> Bool {
        // Distance from point to line segment
        let dx = to.x - from.x
        let dy = to.y - from.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared < 0.001 { return distance(from: point, to: from) < tolerance }
        
        let t = max(0, min(1, ((point.x - from.x) * dx + (point.y - from.y) * dy) / lengthSquared))
        let projection = CGPoint(x: from.x + t * dx, y: from.y + t * dy)
        
        return distance(from: point, to: projection) < tolerance
    }
}
