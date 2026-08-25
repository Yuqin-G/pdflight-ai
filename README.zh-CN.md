# PDFlight AI

<p align="center">
  <img src="Resources/PDFlightIcon.png" width="160" alt="PDFlight 图标">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

PDFlight AI 是一款极轻量的原生 macOS AI 论文阅读器，内置完整的 **Ask PDF** 工作区。它将 AppKit 界面、仅启用 PDF 的 MuPDF 引擎、按论文隔离的 AI 对话、可编辑 Prompt 模式和原生 Markdown/LaTeX 渲染结合起来，同时不使用 WebView、embedding 或 RAG。

**Extremely Light**

| 打开的 PDF 数量 | PDFlight | Skim |
| ---: | ---: | ---: |
| 10 | 165.2 MiB | 934.6 MiB |
| 30 | 338.2 MiB | 2,595.6 MiB |

当前功能：

- 连续垂直滚动，并且只渲染可见页面附近的内容；
- 默认显示的原生文献库侧栏，所有已打开论文同步使用同一宽度，并支持不限层级分类、显示别名、搜索、拖放归档和快速切换；
- 可与文献库切换的层级文档目录和页码跳转；
- 每个文档限制为 12 MiB 的 MuPDF store，以及按字节限制为 12 MiB 的渲染页面缓存；
- 非活动窗口在五秒后释放文本、渲染页面和 MuPDF 缓存；
- PDF 文字选择和复制；
- 选中文字后通过工具栏或 Command-E 直接高亮，无需切换工具模式；
- 全文搜索、结果跳转和页面高亮；
- 支持密码保护的 PDF；
- PDF 内部链接跳转，并可通过 Command-左方向键精确返回跳转前位置；
- 外部链接通过默认浏览器打开；
- 重新打开 PDF 时恢复上次页码、精确阅读位置和缩放比例；
- Retina 渲染、适合宽度、键盘/触控板缩放，以及缩放时的非空白渐进重绘；
- 不同 PDF 默认以标签页形式放在同一窗口；
- 将文字对齐高亮写回为标准 PDF 批注；
- 内嵌 PDF 文字备注批注；
- Command-Z 撤销最近一次高亮或文字备注；
- 默认打开的原生 **Ask PDF** AI 侧栏，后台流式接收并在完成后一次性显示，所有论文共享并记住同一宽度与显示状态，支持按论文显示横向会话标签、单独调节并选择回复文字、编辑或新增 Prompt 模式、原生块级 Markdown/LaTeX 渲染与逐条复制/删除；
- 直接保存，并在关闭存在未保存修改的文档时提示。

## Ask PDF

AI 侧栏默认打开，可以拖动分隔线调整宽度。它的宽度和显示状态会同步到所有已打开论文，并与阅读器窗口尺寸一起在下次启动时恢复。回复区手势缩放默认关闭；在 AI 设置中开启后，可在回复列表上双指捏合，或使用 **Command + 滚轮**，只调整回复正文，不改变输入框和控件字号。设置面板也可直接在 Finder 打开可迁移的聊天记录目录。会话标签后的 **+** 可为当前论文新建会话。按 **Shift-Command-A** 隐藏或重新显示，再点击齿轮填写 OpenAI-compatible Base URL、模型和可选 API key。支持 OpenAI、OpenRouter、DeepSeek、Ollama、LM Studio 这类 chat-completions 接口。

PDFlight 会在后台持续接收流式响应，并实时显示模型活动状态；等生成结束后，再一次性插入并渲染完整的 Markdown/LaTeX 回答，避免未完成的表格和公式反复重排。如果手动停止或连接失败，已经收到的正文仍会保留为部分回复。

每个新会话都默认选中 **No prompt**。Prompt 模式以输入框下方的按钮显示，点击 **Reading** 即可启用中文深度阅读模板；旁边的菜单可以编辑 No prompt、Reading，或新增自定义模式。模板以便于迁移的 JSON 保存，并支持用 `{{title}}` 插入当前 PDF 标题。任何模式都不会自动附加 PDF 页面内容。

当前论文的不同会话以稳定的横向标签显示。标题栏中的缩小/放大按钮只调整并记住回复字号，不会改变输入框。回复采用与 Argus 相同的 macOS 系统字体栈：正文使用 SF Pro（中文自动回退为苹方），代码使用 SF Mono。按回车发送后会保持当前标签，并让最新消息继续可见。

每个 PDF 标签页都有独立的聊天区域，并可创建多个会话。历史按钮会按论文分组显示全部会话，也可以直接在 Finder 中打开存储目录。记录以“每篇论文一个文件”的版本化、格式化 UTF-8 JSON 保存在 `~/Library/Application Support/dev.pdflight.reader/ai-chats`，无需数据库，复制整个目录即可备份或迁移。AI 回复原生渲染标题、列表、引用、表格、代码块、粗体/斜体 Markdown 和 LaTeX 公式，并支持 `\text{…}` 中的中文标签；强调标记可以跨越行内公式，行内公式会嵌在原段落中连续排版，超宽块级公式可以横向滚动。回复文字可以直接选择；用户和助手的消息卡顶部、底部都有复制入口，底部删除操作经确认后会同步更新本地记录。

AI 功能刻意保持轻量：不建立 embedding、不运行 RAG、不开放 MCP 工具、不自动截取或上传 PDF 页面，也不使用 WebView。只有用户明确粘贴、拖入或添加的图片才会发送。API key 保存在 macOS 钥匙串中。

## 文献库

左侧栏默认显示 **Library**，也可以切换为当前 PDF 的 **Outline**。左右侧栏的宽度和显示状态统一属于工作区布局：在任意论文中调整后，其他现有窗口、之后新打开的论文和下次启动都会沿用同一布局。**Recent** 按实际打开时间显示历史论文，File 菜单中也提供 **Open Recent** 和 **Clear Menu**。你可以创建任意层级的分类、添加 PDF，并按显示名、真实文件名或路径搜索；用 Command/Shift 批量选中文献后，可以一次拖放或移动到目标分类。形如 `作者 - 2026 - 论文标题` 的文件默认只显示 `论文标题`。右键论文选择 **Edit display name…** 可设置自定义别名而不重命名 PDF，清空别名即可恢复自动名称。打开过的 PDF 会自动加入 Unfiled。在应用菜单中开启 **Restore Last Session at Launch** 后，下次启动会恢复退出时仍打开的论文标签。文献库和上次会话都以格式化、版本化 JSON 保存在 `~/Library/Application Support/dev.pdflight.reader/`；从文献库移除论文不会删除本地 PDF 文件。

## 下载

从 [GitHub Releases](https://github.com/Yuqin-G/pdflight-ai/releases/latest) 下载最新的 Apple Silicon 构建。PDFlight 要求 macOS 14 或更高版本。当前开源构建使用 ad-hoc 签名；如果 macOS 首次启动时提示无法确认开发者，请按住 Control 点击应用并选择“打开”。

## 构建

要求：macOS 14 或更高版本、Apple Command Line Tools、Git，以及首次检出 MuPDF 时可用的网络连接。

```sh
./Scripts/build-app.sh
open ./dist/PDFlight.app
```

构建脚本会检出 MuPDF 1.28.2，并且只编译 PDFlight 所需的原生库。EPUB/HTML、XPS、SVG、JavaScript、OCR 和条形码功能不会被包含。`tofu` 构建保留 Base 14 与中日韩字体回退，同时省略无关的回退字体。

安装本地构建：

```sh
ditto ./dist/PDFlight.app /Applications/PDFlight.app
```

使用 [`duti`](https://github.com/moretension/duti) 将其设置为默认 PDF 阅读器：

```sh
duti -s dev.pdflight.reader com.adobe.pdf viewer
duti -s dev.pdflight.reader com.adobe.pdf editor
duti -s dev.pdflight.reader com.adobe.pdf shell
```

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开 | Command-O |
| 保存 | Command-S |
| 撤销最近一次批注 | Command-Z |
| 复制所选文字 | Command-C |
| 搜索 | Command-F |
| 搜索框内下一条/上一条结果 | Return / Shift-Return |
| 下一条/上一条搜索结果 | Command-G / Shift-Command-G |
| 编辑搜索或聊天文字时移动光标 | 左/右方向键 |
| 上一页/下一页 | 左/右方向键 |
| 链接跳转后返回 | Command-左方向键 |
| 缩放 | Command-加号/减号 |
| 适合宽度 | Command-0 |
| 高亮所选文字 | Command-E |
| 在 Google Scholar 查找当前论文及其被引入口 | 工具栏学士帽按钮 |
| 显示/隐藏 Ask PDF | Shift-Command-A |
| AI 设置 | Command-逗号 |
| 文字备注模式 | N |

## 架构

`DocumentEngine` 是文档 seam，负责页面检查、目录、文字提取、搜索、渲染、链接、批注、密码、内存释放和保存。`MuPDFDocument` 是第一个 adapter。`RenderScheduler` 负责合并进行中的相同请求，并维护按字节限制的 LRU 缓存。`DocumentCanvasView` 通过只保留视口附近的渲染内容实现页面位图虚拟化。`ReadingPositionStore` 与 `PaperLibraryStore` 使用原子 JSON 保存本地状态。`PDFlightAI` 负责显式请求构造、OpenAI-compatible 流式请求、钥匙串配置和按 PDF 隔离的对话记录。AppKit 仅通过这些 interface 与底层交互。


## 许可证

由于链接了 MuPDF，PDFlight 使用 AGPL-3.0-or-later 许可证发布。详见 `LICENSE` 和 `Vendor/mupdf` 下的 MuPDF 声明。
