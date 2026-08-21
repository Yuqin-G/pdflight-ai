import AppKit
import PDFlightAI

@MainActor
final class AIPromptTemplateEditorView: NSView {
    private let nameField = NSTextField()
    private let promptTextView = NSTextView()

    init(template: AIPromptTemplate) {
        super.init(frame: NSRect(x: 0, y: 0, width: 580, height: 410))

        nameField.stringValue = template.name
        nameField.placeholderString = "Mode name"
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = label("Name")
        let promptLabel = label("Prompt template")
        let hint = NSTextField(
            wrappingLabelWithString: "Use {{title}} where the current PDF title should be inserted. An empty template sends no additional prompt."
        )
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.translatesAutoresizingMaskIntoConstraints = false

        promptTextView.string = template.prompt
        promptTextView.font = .systemFont(ofSize: 12.5)
        promptTextView.isRichText = false
        promptTextView.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView.isAutomaticDashSubstitutionEnabled = false
        promptTextView.textContainerInset = NSSize(width: 9, height: 9)
        promptTextView.isVerticallyResizable = true
        promptTextView.isHorizontallyResizable = false
        promptTextView.autoresizingMask = [.width]
        promptTextView.textContainer?.widthTracksTextView = true

        let promptScrollView = NSScrollView()
        promptScrollView.documentView = promptTextView
        promptScrollView.hasVerticalScroller = true
        promptScrollView.autohidesScrollers = true
        promptScrollView.borderType = .bezelBorder
        promptScrollView.translatesAutoresizingMaskIntoConstraints = false
        promptTextView.frame = promptScrollView.contentView.bounds

        addSubview(nameLabel)
        addSubview(nameField)
        addSubview(promptLabel)
        addSubview(hint)
        addSubview(promptScrollView)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor),
            promptLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            hint.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 3),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor),
            promptScrollView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 7),
            promptScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            promptScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            promptScrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var templateName: String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var prompt: String {
        promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var initialFirstResponder: NSView { nameField }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}
