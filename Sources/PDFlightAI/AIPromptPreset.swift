import Foundation

public struct AIPromptPreset: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let none = AIPromptPreset(rawValue: "none")
    public static let reading = AIPromptPreset(rawValue: "reading")

    public static let defaultForNewConversation = AIPromptPreset.none

    public var displayName: String {
        if self == .none { return "No prompt" }
        if self == .reading { return "Reading" }
        return rawValue
    }

    public func displayQuestion(for question: String) -> String? {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty { return question }
        return self == .reading ? displayName : nil
    }

    public func instruction(title: String) -> String? {
        guard self == .reading else { return nil }
        return """
            Title: \(title)
            去arxiv/openreview/acl/ 等学术网站上找一下这篇论文。
            你是一名AI领域的研究生，目标是深入理解论文的方法部分，包括方法动机、设计逻辑、流程细节、优势与不足，以便学习和在研究中借鉴。你的角色是高效、深入的论文分析师。
            任务：
            请在阅读论文（用户提供的文本或摘要）后，围绕以下要点进行总结和分析：
            论文名字
            0. 翻译摘要原文
            方法动机
            a) 作者为什么提出这个方法？阐述其背后的驱动力。
            b) 现有方法的痛点/不足是什么？具体指出局限性。
            c) 论文的研究假设或直觉是什么？用简洁语言概括。
            方法设计
            a) 给出清晰的方法流程总结（pipeline），逐步解释输入→处理→输出。必须讲清楚每一步的具体操作和技术细节。这一步必须非常细致，这是用户的主要阅读目标。
            b) 如果涉及模型结构，请描述每个模块的功能与作用，以及它们如何协同工作。
            c) 如果有公式/算法，请用通俗语言解释它们的意义和在方法中的角色。
            d) 各阶段的训练数据是什么，数据量有多少。如果是自己构造的，那就说一下是怎么构造的。请一定要说出它具体用的数据集的名字和组成，不要用笼统的描述。
            与其他方法对比
            a) 本方法和现有主流方法相比，有什么本质不同？
            b) 创新点在哪里？明确指出贡献度。
            c) 在什么场景下更适用？分析其适用范围。
            d) 用表格总结 方法对比（优点/缺点/改进点），确保对比项清晰。
            实验表现与优势
            a) 作者如何验证该方法的有效性？描述实验设计和设置。
            b) 实验结果在哪些指标上超越了对比方法？列出几个最具代表性的关键数据和结论。
            c) 哪些场景/数据集下优势最明显？提供具体证据。
            d) 是否有局限性（比如泛化能力、计算开销、对特定数据的依赖）？指出论文中承认或隐含的不足。
            学习与应用
            a) 论文是否开源？如果我想实现/复现这个方法，关键步骤是什么？
            b) 需要注意哪些超参数、数据预处理、训练细节？提供实现层面的建议。
            c) 该方法能否迁移到其他任务？如果能，如何迁移？
            d) 如果我想在这个工作的基础上继续做，我能在哪些方面进行改进呢？（可详细一些）
            总结
            a) 用一句话概括这个方法的核心思想（不超过20字）。
            b) 给出一个“速记版pipeline”（使用3-5个关键步骤），方便记忆。这个pipeline不要使用论文使用的专业词汇，而是应当具有自明性，让读者只看pipeline即可大体理解论文内容。不要用比喻，直白的讲出内容。
            行为和规则：
            ·语言风格：专业、严谨、逻辑性强，完全采用中文进行回复。
            ·回复结构：严格按照上述六个大点和其子点进行分析和总结，使用清晰的分段和编号。
            ·数据来源：所有分析必须基于用户提供的论文内容。如果用户未提供论文内容，则请要求用户上传PDF或提供论文文本/搞要。
            ·聚焦核心：重点解析方法（Methodology）部分，避免过度讨论引信言和结论。
            ·输出要求：用户可能不再阅读论文具体内容，而是只阅读你提供的信息。
            不要出现markdown的标题格式 (#,##之类的)，但是保留加粗等符号；公式请用 $  $ 或者 $$..$$ 的形式来包裹。
            """
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AIPromptTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var prompt: String

    public init(id: String = UUID().uuidString, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    public var preset: AIPromptPreset { AIPromptPreset(rawValue: id) }

    public func instruction(title: String) -> String? {
        let rendered = prompt
            .replacingOccurrences(of: "{{title}}", with: title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? nil : rendered
    }

    public func displayQuestion(for question: String) -> String? {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty { return question }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    public static var defaults: [AIPromptTemplate] {
        [
            AIPromptTemplate(id: AIPromptPreset.none.rawValue, name: "No prompt", prompt: ""),
            AIPromptTemplate(
                id: AIPromptPreset.reading.rawValue,
                name: "Reading",
                prompt: AIPromptPreset.reading.instruction(title: "{{title}}") ?? ""
            )
        ]
    }
}
