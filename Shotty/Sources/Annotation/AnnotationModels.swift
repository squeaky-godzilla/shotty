import AppKit

// MARK: - Tool

enum AnnotationTool: Equatable {
    case pen
    case text
    case sticker
    case eraser
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

// MARK: - Undo action stack entry

private enum UndoAction {
    case stroke
    case text
    case sticker
}

// MARK: - Canvas model

class AnnotationModel {
    var strokes:  [StrokeAnnotation]  = []
    var texts:    [TextAnnotation]    = []
    var stickers: [StickerAnnotation] = []

    var currentTool:   AnnotationTool = .pen
    var currentColor:  NSColor        = .systemRed
    var lineWidth:     CGFloat        = 3.0
    var fontSize:      CGFloat        = 18.0
    var selectedEmoji: String         = "❤️"

    var activeStroke: StrokeAnnotation?

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

    // MARK: Sticker

    func addSticker(at point: CGPoint) {
        let s = StickerAnnotation(emoji: selectedEmoji, center: point, size: 36)
        stickers.append(s)
        undoStack.append(.sticker)
    }

    // MARK: Undo

    func undoLast() {
        guard let last = undoStack.last else { return }
        undoStack.removeLast()
        switch last {
        case .stroke:  if !strokes.isEmpty  { strokes.removeLast()  }
        case .text:    if !texts.isEmpty    { texts.removeLast()    }
        case .sticker: if !stickers.isEmpty { stickers.removeLast() }
        }
    }
}
