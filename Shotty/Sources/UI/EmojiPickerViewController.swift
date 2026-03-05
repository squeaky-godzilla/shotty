import AppKit

/// A compact grid of common reaction emojis shown as a popover.
class EmojiPickerViewController: NSViewController {
    private let onSelect: (String) -> Void
    private var currentSelected: String

    // Grouped reacji + common emojis
    static let emojis: [String] = [
        // Reactions
        "❤️", "👍", "👎", "😂", "😮", "😢", "😡", "🎉",
        // Faces
        "😀", "😍", "🤔", "🤯", "🥳", "😎", "🤣", "😭",
        // Symbols
        "✅", "❌", "⚠️", "🔥", "💯", "🚀", "⭐", "💡",
        // Arrows / shapes
        "👉", "👈", "👆", "👇", "🖊️", "📌", "🔴", "🟡",
        // Misc
        "🐛", "💀", "👻", "🤦", "🙏", "💪", "🎯", "🏆",
    ]

    init(selected: String, onSelect: @escaping (String) -> Void) {
        self.currentSelected = selected
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        preferredContentSize = CGSize(width: 280, height: 220)

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 2
        grid.columnSpacing = 2

        let cols = 8
        let allEmojis = Self.emojis
        var row: [NSView] = []

        for (i, emoji) in allEmojis.enumerated() {
            let btn = NSButton(title: emoji, target: self, action: #selector(emojiTapped(_:)))
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 22)
            btn.toolTip = emoji
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 32),
                btn.heightAnchor.constraint(equalToConstant: 32),
            ])
            row.append(btn)
            if row.count == cols || i == allEmojis.count - 1 {
                // Pad row to cols
                while row.count < cols { row.append(NSView()) }
                grid.addRow(with: row)
                row = []
            }
        }

        let scrollView = NSScrollView()
        scrollView.documentView = grid
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            container.widthAnchor.constraint(equalToConstant: 280),
            container.heightAnchor.constraint(equalToConstant: 220),
        ])

        view = container
    }

    @objc private func emojiTapped(_ sender: NSButton) {
        onSelect(sender.title)
        dismiss(self)
    }
}
