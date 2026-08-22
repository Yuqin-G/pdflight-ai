import AppKit
import PDFlightAI
import PDFlightCore
import iosMath

private struct AppSelfCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
enum PDFlightAppSelfChecks {
    private static let labeledGRPOLatex = """
    \\mathcal{J}_{GRPO}(\\theta) = \\mathbb{E} \\left[ \\frac{1}{G} \\sum_{i=1}^G \\frac{1}{|o_i|} \\sum_{t=1}^{|o_i|} \\left( \\underbrace{\\min \\left( \\rho_{i,t} \\hat{A}_i, \\text{clip}(\\rho_{i,t}, 1-\\epsilon, 1+\\epsilon) \\hat{A}_i \\right)}_{\\text{策略优化部分 (类似 PPO)}} - \\underbrace{\\beta \\mathbb{D}_{KL}(\\pi_\\theta || \\pi_{ref})}_{\\text{KL 散度惩罚}} \\right) \\right]
    """
    private static let casesLatex = #"r = \begin{cases} 1, & \left| \hat{d} - d \right| < \epsilon \\ 0, & \text{otherwise} \end{cases}"#

    static func mathRendering() throws {
        IOSMathResourceLocator.install()
        let formulas = [
            "r_n^{\\text{final}} =",
            "W_{ij} = \\exp(-d^2(f_i, f_j)/2",
            casesLatex,
            labeledGRPOLatex
        ]
        for formula in formulas {
            let label = MTMathUILabel()
            label.latex = formula
            guard label.error == nil else {
                throw AppSelfCheckFailure(
                    description: "iosMath rejected recovered formula \(formula): \(label.error!)"
                )
            }
        }
        print("PASS: iosMath accepts complete and recovered Qwen formulas")
    }

    static func sidebarLayout() throws {
        guard ReaderCopyRouting.destination(
            editorSelectionLength: 12,
            hasPDFSelection: true
        ) == .textEditor,
        ReaderCopyRouting.destination(
            editorSelectionLength: 0,
            hasPDFSelection: true
        ) == .pdfSelection,
        ReaderCopyRouting.destination(
            editorSelectionLength: nil,
            hasPDFSelection: false
        ) == .none else {
            throw AppSelfCheckFailure(
                description: "An empty chat editor selection still intercepts PDF copy"
            )
        }

        let selectionActionBar = PDFSelectionActionBar(frame: NSRect(
            origin: .zero,
            size: PDFSelectionActionBar.preferredSize
        ))
        guard selectionActionBar.actionTitlesForLayoutCheck() == ["Copy", "Highlight", "Ask AI"] else {
            throw AppSelfCheckFailure(
                description: "The PDF selection action bar is missing copy, highlight, or Ask AI"
            )
        }
        let placementContainer = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let selectionAnchor = NSRect(x: 300, y: 350, width: 100, height: 30)
        let actionFrame = PDFSelectionActionBarPlacement.frame(
            anchor: selectionAnchor,
            in: placementContainer,
            barSize: PDFSelectionActionBar.preferredSize
        )
        guard placementContainer.insetBy(dx: 9, dy: 9).contains(actionFrame) else {
            throw AppSelfCheckFailure(
                description: "The PDF selection action bar can escape the document pane"
            )
        }
        guard actionFrame.minX >= selectionAnchor.maxX + PDFSelectionActionBarPlacement.gap - 0.5,
              actionFrame.maxY <= selectionAnchor.minY - PDFSelectionActionBarPlacement.gap + 0.5 else {
            throw AppSelfCheckFailure(
                description: "The PDF selection action bar is not anchored at the selection's lower-right corner"
            )
        }

        guard let scholarURL = GoogleScholarLinkBuilder.paperSearchURL(
            fileNameOrDisplayTitle: "Ming 等 - 2026 - Yesterday's Shield, Today's Spear"
        ),
        scholarURL.host == "scholar.google.com",
        URLComponents(url: scholarURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" })?
            .value == "\"Yesterday's Shield, Today's Spear\"" else {
            throw AppSelfCheckFailure(
                description: "Google Scholar links do not use the paper's clean display title"
            )
        }

        guard ReaderPageKeyRouting.action(
            keyCode: 123,
            modifiers: [],
            isEditingText: true
        ) == nil,
        ReaderPageKeyRouting.action(
            keyCode: 124,
            modifiers: [],
            isEditingText: true
        ) == nil,
        ReaderPageKeyRouting.action(
            keyCode: 123,
            modifiers: [],
            isEditingText: false
        ) == .previous,
        ReaderPageKeyRouting.action(
            keyCode: 124,
            modifiers: [],
            isEditingText: false
        ) == .next else {
            throw AppSelfCheckFailure(
                description: "Arrow keys do not distinguish text editing from page navigation"
            )
        }

        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1_020, height: 700))
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let library = NSView()
        library.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 2_000))
        let askSidebar = AIChatSidebarView()

        splitView.addArrangedSubview(library)
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(askSidebar)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        let widthSuiteName = "dev.pdflight.reader.sidebar-self-check.\(UUID().uuidString)"
        guard let widthDefaults = UserDefaults(suiteName: widthSuiteName) else {
            throw AppSelfCheckFailure(description: "Could not create isolated sidebar defaults")
        }
        defer { widthDefaults.removePersistentDomain(forName: widthSuiteName) }
        guard !AIReplyGestureZoomPreference.isEnabled(defaults: widthDefaults) else {
            throw AppSelfCheckFailure(
                description: "Reply gesture zoom is not disabled by default"
            )
        }
        AIReplyGestureZoomPreference.setEnabled(
            true,
            defaults: widthDefaults,
            broadcast: false
        )
        guard AIReplyGestureZoomPreference.isEnabled(defaults: widthDefaults) else {
            throw AppSelfCheckFailure(
                description: "Reply gesture zoom preference does not survive settings changes"
            )
        }
        let widthCoordinator = ReaderWorkspaceLayoutCoordinator(defaults: widthDefaults)
        let navigationConstraints = ReaderNavigationSidebarSizing.flexibleConstraints(
            for: library,
            coordinator: widthCoordinator
        )
        guard navigationConstraints.contains(where: { $0.relation == .equal }) else {
            throw AppSelfCheckFailure(
                description: "Paper windows do not retain one shared library sidebar width"
            )
        }
        NSLayoutConstraint.activate(navigationConstraints)
        splitView.layoutSubtreeIfNeeded()
        let leftBefore = library.frame.width
        let secondLibrary = NSView()
        let secondConstraints = ReaderNavigationSidebarSizing.flexibleConstraints(
            for: secondLibrary,
            coordinator: widthCoordinator
        )
        widthCoordinator.setNavigationWidth(330, broadcast: false)
        splitView.layoutSubtreeIfNeeded()
        guard library.frame.width > leftBefore + 50 else {
            throw AppSelfCheckFailure(
                description: "The library sidebar divider cannot resize the left pane"
            )
        }
        guard secondConstraints.first(where: { $0.relation == .equal })?.constant == 330,
              ReaderWorkspaceLayoutCoordinator(defaults: widthDefaults).navigationWidth == 330 else {
            throw AppSelfCheckFailure(
                description: "Library sidebar width does not synchronize or survive relaunch"
            )
        }
        let secondAskSidebar = AIChatSidebarView()
        let secondAskWidth = widthCoordinator.bindAISidebar(secondAskSidebar)
        let askWidth = widthCoordinator.bindAISidebar(askSidebar)
        askWidth.isActive = true
        splitView.layoutSubtreeIfNeeded()

        let before = askSidebar.frame.width
        widthCoordinator.setAIWidth(420, broadcast: false)
        splitView.layoutSubtreeIfNeeded()
        let after = askSidebar.frame.width
        guard after > before + 60,
              secondAskWidth.constant == 420,
              ReaderWorkspaceLayoutCoordinator(defaults: widthDefaults).aiWidth == 420 else {
            throw AppSelfCheckFailure(
                description: "Ask PDF width does not synchronize or survive relaunch: before=\(before), after=\(after)"
            )
        }
        guard widthCoordinator.navigationVisible, widthCoordinator.aiVisible else {
            throw AppSelfCheckFailure(
                description: "A new workspace does not show the saved sidebars by default"
            )
        }
        widthCoordinator.setNavigationVisible(false, broadcast: false)
        widthCoordinator.setAIVisible(false, broadcast: false)
        let reopenedLayout = ReaderWorkspaceLayoutCoordinator(defaults: widthDefaults)
        guard !reopenedLayout.navigationVisible, !reopenedLayout.aiVisible else {
            throw AppSelfCheckFailure(
                description: "Sidebar visibility does not survive relaunch"
            )
        }
        let assistantMessage = AIChatMessage(
            role: .assistant,
            content: "A response that must keep a safe inset from both sidebar dividers."
        )
        askSidebar.install([assistantMessage])
        askSidebar.setMessageActivity(
            id: assistantMessage.id,
            phase: .thinking,
            identity: "Universal Web API · qwen"
        )
        splitView.layoutSubtreeIfNeeded()
        guard let messageFrame = askSidebar.messageFramesForLayoutCheck().first,
              messageFrame.minX >= 18,
              messageFrame.maxX <= askSidebar.bounds.maxX - 12 else {
            throw AppSelfCheckFailure(
                description: "An Ask PDF message overlaps a sidebar divider"
            )
        }

        let older = AIConversation(
            id: "older",
            title: "Earlier question",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var active = AIConversation(
            id: "active",
            title: "Current question",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        askSidebar.setConversations([older, active], selectedID: active.id)
        guard askSidebar.newConversationButtonFollowsTabsForLayoutCheck() else {
            throw AppSelfCheckFailure(
                description: "The new-conversation plus button is not placed after conversation tabs"
            )
        }
        active.updatedAt = Date(timeIntervalSince1970: 300)
        askSidebar.setConversations([older, active], selectedID: active.id)
        guard askSidebar.selectedConversationIDForLayoutCheck() == active.id else {
            throw AppSelfCheckFailure(
                description: "Refreshing conversations reset the active conversation"
            )
        }

        let customPrompt = AIPromptTemplate(
            id: "methods",
            name: "Methods",
            prompt: "Explain {{title}}"
        )
        askSidebar.setPromptTemplates(
            AIPromptTemplate.defaults + [customPrompt],
            selectedPreset: customPrompt.preset
        )
        guard askSidebar.selectedPromptPresetForLayoutCheck() == customPrompt.preset else {
            throw AppSelfCheckFailure(
                description: "A custom prompt mode could not be selected as a button"
            )
        }

        let originalFontSize = askSidebar.messageFontSizeForLayoutCheck()
        let originalComposerFontSize = askSidebar.composerFontSizeForLayoutCheck()
        askSidebar.setMessageFontSizeForLayoutCheck(originalFontSize + 3)
        guard askSidebar.messageFontSizeForLayoutCheck() == originalFontSize + 3 else {
            throw AppSelfCheckFailure(
                description: "Ask PDF message font size did not change"
            )
        }
        guard askSidebar.composerFontSizeForLayoutCheck() == originalComposerFontSize else {
            throw AppSelfCheckFailure(
                description: "Changing reply text size also changed the composer font"
            )
        }
        askSidebar.magnifyMessageContentForLayoutCheck(by: 1.5)
        guard askSidebar.messageFontSizeForLayoutCheck() == originalFontSize + 3 else {
            throw AppSelfCheckFailure(
                description: "Reply gestures remain active when disabled in settings"
            )
        }
        askSidebar.setReplyGestureZoomEnabled(true)
        askSidebar.magnifyMessageContentForLayoutCheck(by: 1.5)
        guard askSidebar.messageFontSizeForLayoutCheck() == originalFontSize + 4.5,
              askSidebar.composerFontSizeForLayoutCheck() == originalComposerFontSize else {
            throw AppSelfCheckFailure(
                description: "Message-area magnification changed controls or the composer"
            )
        }
        askSidebar.setMessageFontSizeForLayoutCheck(originalFontSize)

        let settingsForm = AISettingsFormView(
            configuration: AIProviderConfiguration(
                baseURL: "http://127.0.0.1:8199/v1",
                model: "qwen"
            ),
            apiKey: "",
            replyGestureZoomEnabled: false
        )
        var finderActionTriggered = false
        settingsForm.onOpenChatHistory = { finderActionTriggered = true }
        settingsForm.triggerOpenChatHistoryForLayoutCheck()
        guard finderActionTriggered, !settingsForm.replyGestureZoomEnabled else {
            throw AppSelfCheckFailure(
                description: "AI Settings does not expose Finder history or the default-off zoom toggle"
            )
        }

        let messages = (0..<30).map { index in
            AIChatMessage(
                id: "message-\(index)",
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "Message \(index): keep the newest conversation content visible after Return."
            )
        }
        askSidebar.install(messages)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let latest = messages.last,
              askSidebar.isMessageVisibleForLayoutCheck(id: latest.id) else {
            throw AppSelfCheckFailure(
                description: "Submitting a message scrolled away from the latest conversation content"
            )
        }

        let markdown = AIChatMessage(
            id: "markdown-check",
            role: .assistant,
            content: "# Method\n\n- Encode frames\n- Rank evidence\n\n**Result**"
        )
        askSidebar.install([markdown])
        let renderedMarkdown = askSidebar.renderedMessageTextForLayoutCheck(id: markdown.id)
        guard askSidebar.messageContentContainsSelectableTextForLayoutCheck(id: markdown.id) else {
            throw AppSelfCheckFailure(
                description: "Assistant reply text cannot be selected and copied"
            )
        }
        guard askSidebar.messageHasBottomActionsForLayoutCheck(id: markdown.id) else {
            throw AppSelfCheckFailure(
                description: "Message cards are missing bottom copy and delete actions"
            )
        }
        var deletedMessageID: String?
        askSidebar.onDeleteMessage = { deletedMessageID = $0 }
        askSidebar.triggerDeleteMessageForLayoutCheck(id: markdown.id)
        guard deletedMessageID == markdown.id else {
            throw AppSelfCheckFailure(
                description: "The message delete action is not connected to chat history"
            )
        }
        guard !renderedMarkdown.contains("# Method"),
              renderedMarkdown.contains("• Encode frames"),
              renderedMarkdown.contains("Result") else {
            throw AppSelfCheckFailure(
                description: "Assistant replies are not rendering block Markdown"
            )
        }

        let comparisonTable = AIChatMessage(
            id: "table-layout-check",
            role: .assistant,
            content: """
            | 方法类别 | 代表方法 | 优点 | 缺点 | SESG 的改进点 |
            | --- | --- | --- | --- | --- |
            | **静态护栏** | LlamaGuard, ShieldGemma | 推理开销低，对已知威胁防御稳定 | 无法适应新形式的越狱或新危害类别，更新依赖漫长的人工流程 | 引入自动化闭环，将更新周期从数周缩短至数小时 |
            """
        )
        splitView.frame.size.width = 1_700
        askWidth.constant = 1_000
        askSidebar.install([comparisonTable])
        splitView.layoutSubtreeIfNeeded()
        let tableWidths = askSidebar.tableColumnWidthsForLayoutCheck(id: comparisonTable.id)
        guard tableWidths.count == 5,
              tableWidths.min() ?? 0 >= 120 else {
            throw AppSelfCheckFailure(
                description: "Markdown table columns collapse into character-by-character text: \(tableWidths)"
            )
        }
        guard askSidebar.messageHasFontTraitForLayoutCheck(
            id: comparisonTable.id,
            text: "静态护栏",
            trait: .boldFontMask
        ) else {
            throw AppSelfCheckFailure(
                description: "Inline Markdown is not rendered inside table cells"
            )
        }

        let displayMath = AIChatMessage(
            id: "display-math-check",
            role: .assistant,
            content: "$$ \(labeledGRPOLatex) $$"
        )
        askSidebar.install([displayMath])
        guard askSidebar.renderedMathLatexForLayoutCheck(id: displayMath.id) == [labeledGRPOLatex] else {
            throw AppSelfCheckFailure(
                description: "Unicode-labeled display math did not reach the reply renderer"
            )
        }
        guard askSidebar.hasScrollableDisplayMathForLayoutCheck(id: displayMath.id) else {
            throw AppSelfCheckFailure(
                description: "Wide display math is clipped instead of horizontally scrollable"
            )
        }

        let multilineCases = AIChatMessage(
            id: "multiline-cases-check",
            role: .assistant,
            content: #"""
            在 SFT 之后，可以设置容差：

            $$
            r = \begin{cases}
            1, & \left| \hat{d} - d \right| < \epsilon \\
            0, & \text{otherwise}
            \end{cases}
            $$

            或者使用平滑奖励。
            """#
        )
        askSidebar.install([multilineCases])
        guard askSidebar.renderedMathLatexForLayoutCheck(id: multilineCases.id) == [casesLatex],
              !askSidebar.renderedMessageTextForLayoutCheck(id: multilineCases.id).contains("$$") else {
            throw AppSelfCheckFailure(
                description: "Standalone multiline $$ cases remain visible instead of rendering as one formula"
            )
        }

        let inlineMath = AIChatMessage(
            id: "inline-math-check",
            role: .assistant,
            content: "对于同一个 prompt $q$，采样 $G$ 个输出 $\\{o_1,o_2,\\ldots,o_G\\}$。"
        )
        askSidebar.install([inlineMath])
        guard askSidebar.renderedBlockCountForLayoutCheck(id: inlineMath.id) == 1 else {
            throw AppSelfCheckFailure(
                description: "Inline math fragments one paragraph into vertical reply blocks"
            )
        }
        guard askSidebar.inlineMathAttachmentCountForLayoutCheck(id: inlineMath.id) == 3 else {
            throw AppSelfCheckFailure(
                description: "Inline equations were not embedded inside the paragraph"
            )
        }

        let emphasizedMath = AIChatMessage(
            id: "emphasized-math-check",
            role: .assistant,
            content: "**$x$ 的计算方式**，以及 *斜体 $y$ 说明*"
        )
        askSidebar.install([emphasizedMath])
        let emphasizedText = askSidebar.renderedMessageTextForLayoutCheck(id: emphasizedMath.id)
        guard !emphasizedText.contains("**"),
              askSidebar.messageHasFontTraitForLayoutCheck(
                id: emphasizedMath.id,
                text: "计算方式",
                trait: .boldFontMask
              ) else {
            throw AppSelfCheckFailure(
                description: "Bold Markdown markers spanning inline math remain visible"
            )
        }
        guard !emphasizedText.contains("*斜体"),
              askSidebar.messageHasFontTraitForLayoutCheck(
                id: emphasizedMath.id,
                text: "斜体",
                trait: .italicFontMask
              ) else {
            throw AppSelfCheckFailure(
                description: "Italic Markdown markers spanning inline math remain visible"
            )
        }

        let libraryStore = PaperLibraryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pdflight-library-drag-self-check-\(UUID().uuidString).json")
        )
        let librarySidebar = LibrarySidebarView(store: libraryStore)
        guard librarySidebar.paperDraggingEnabledForLayoutCheck() else {
            throw AppSelfCheckFailure(
                description: "Library papers are not registered for collection drag and drop"
            )
        }
        print(
            "PASS: Ask PDF keeps its active conversation, latest message, width, and divider insets"
        )
    }
}
