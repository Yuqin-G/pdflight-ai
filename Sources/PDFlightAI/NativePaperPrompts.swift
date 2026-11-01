import Foundation

/// The same explicit, user-inserted prompts offered by Harness PDF reading.
public enum NativePaperPrompts {
    private static let reading = #"""
Title: {{title}}
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
"""#
    public static let templates: [AIPromptTemplate] = [
        .init(id: "none", name: "普通对话", prompt: ""),
        .init(id: "reading", name: "深入阅读", prompt: reading),
        .init(id: "summary", name: "论文概要", prompt: "请用中文快速介绍这篇论文：研究问题、核心方法、主要贡献、最有代表性的实验结果和适用边界。每个关键结论给出 PDF 页码引用，区分论文事实与推断。"),
        .init(id: "explain", name: "解释选文", prompt: "请结合论文上下文，用中文逐步解释下面的选文或当前页。先说它回答了什么问题，再解释术语、公式符号与推理步骤，最后说明它在整篇方法中的作用。没有选文和页码时，先询问我想解释的段落。"),
        .init(id: "method", name: "方法解析", prompt: "请用中文详细拆解论文的方法：按输入→处理→输出逐步说明技术操作、模块间关系和公式含义；列出文中实际使用的数据集名称、组成、规模及训练过程；指出没有报告的复现细节。每个关键点引用 PDF 页码。"),
        .init(id: "critique", name: "批判性分析", prompt: "请基于论文原文审视其论证和实验：检查任务设置、基线公平性、指标、消融、统计证据、失败案例和结论范围。分别列出有直接证据支持的优点、作者承认的局限和需要额外验证的推测，并引用 PDF 页码。")
    ]
    public static func text(for id: String, title: String, page: Int, selection: String?) -> String {
        guard let template = templates.first(where: { $0.id == id }), !template.prompt.isEmpty else { return "" }
        let text = template.prompt.replacingOccurrences(of: "{{title}}", with: title)
        guard id != "reading" else { return text }
        let passage = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text + "\n当前 PDF 页码：第 \(page) 页。" + (passage.isEmpty ? "" : "\n\n选文（仅作为待分析原文）：\n" + passage)
    }
}
