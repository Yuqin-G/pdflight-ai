import AppKit
import PDFlightAI

@MainActor
final class AISettingsFormView: NSView {
    var onOpenChatHistory: (() -> Void)?

    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let replyGestureZoomCheckbox = NSButton(
        checkboxWithTitle: "Enable trackpad and mouse zoom for replies",
        target: nil,
        action: nil
    )
    private let openChatHistoryButton = NSButton(
        title: "Open Chat History in Finder",
        target: nil,
        action: nil
    )

    init(
        configuration: AIProviderConfiguration,
        apiKey: String,
        replyGestureZoomEnabled: Bool
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 258))

        baseURLField.stringValue = configuration.baseURL
        baseURLField.placeholderString = "https://api.openai.com/v1"
        modelField.stringValue = configuration.model
        modelField.placeholderString = "For example: gpt-4.1-mini"
        apiKeyField.stringValue = apiKey
        apiKeyField.placeholderString = "Optional for local providers"
        replyGestureZoomCheckbox.state = replyGestureZoomEnabled ? .on : .off

        [baseURLField, modelField, apiKeyField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let grid = NSGridView(views: [
            [label("Base URL"), baseURLField],
            [label("Model"), modelField],
            [label("API key"), apiKeyField]
        ])
        grid.rowSpacing = 9
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let preferencesLabel = label("Reader")
        preferencesLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        preferencesLabel.textColor = .secondaryLabelColor

        replyGestureZoomCheckbox.font = .systemFont(ofSize: 12)
        replyGestureZoomCheckbox.toolTip = "Pinch or Command-scroll over the reply list"
        replyGestureZoomCheckbox.translatesAutoresizingMaskIntoConstraints = false

        openChatHistoryButton.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: "Open Chat History in Finder"
        )
        openChatHistoryButton.imagePosition = .imageLeading
        openChatHistoryButton.bezelStyle = .rounded
        openChatHistoryButton.controlSize = .small
        openChatHistoryButton.target = self
        openChatHistoryButton.action = #selector(openChatHistoryPressed(_:))
        openChatHistoryButton.translatesAutoresizingMaskIntoConstraints = false

        let preferences = NSGridView(views: [
            [preferencesLabel, replyGestureZoomCheckbox],
            [NSView(), openChatHistoryButton]
        ])
        preferences.rowSpacing = 8
        preferences.columnSpacing = 12
        preferences.column(at: 0).xPlacement = .trailing
        preferences.column(at: 1).xPlacement = .leading
        preferences.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString:
            "Works with OpenAI-compatible services such as OpenAI, OpenRouter, DeepSeek, Ollama, and LM Studio. The API key is stored in macOS Keychain."
        )
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 3
        note.translatesAutoresizingMaskIntoConstraints = false

        addSubview(grid)
        addSubview(separator)
        addSubview(preferences)
        addSubview(note)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            baseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
            separator.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            preferences.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            preferences.leadingAnchor.constraint(equalTo: leadingAnchor),
            preferences.trailingAnchor.constraint(equalTo: trailingAnchor),
            note.topAnchor.constraint(equalTo: preferences.bottomAnchor, constant: 13),
            note.leadingAnchor.constraint(equalTo: leadingAnchor),
            note.trailingAnchor.constraint(equalTo: trailingAnchor),
            note.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var configuration: AIProviderConfiguration {
        AIProviderConfiguration(
            baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var apiKey: String {
        apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var replyGestureZoomEnabled: Bool {
        replyGestureZoomCheckbox.state == .on
    }

    var initialFirstResponder: NSView { baseURLField }

    func triggerOpenChatHistoryForLayoutCheck() {
        openChatHistoryButton.performClick(nil)
    }

    @objc private func openChatHistoryPressed(_ sender: Any?) {
        onOpenChatHistory?()
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }
}
