# PDFlight AI

<p align="center">
  <img src="Resources/PDFlightIcon.png" width="160" alt="PDFlight 图标">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

PDFlight AI 是一款 macOS PDF 阅读器，使用 AppKit 和 MuPDF 显示文献。右侧 **Ask PDF** 直接嵌入本机 DeepSeek Harness 的 PDF 阅读对话，使用 Harness 原有的主题、会话、模型和阅读提示词。

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
- 直接嵌入 DeepSeek Harness PDF 阅读对话的 **Ask PDF** 侧栏，包含原有会话标签、模型、提示词、附件和主题；
- 直接保存，并在关闭存在未保存修改的文档时提示。

## Ask PDF

侧栏嵌入正在运行的 DeepSeek Harness Desktop 的 PDF 阅读对话。请先在 Harness 中启用 `@local/pdf-reading-mode` 插件；如果尚未安装连接插件，可以在侧栏点击 **安装连接插件**，也可以运行 `node scripts/install-harness-bridge.mjs`。连接插件加入现有桌面配置，复用同一个 Harness 会话存储。

首次打开论文时，PDFlight 会根据 PDF 内容匹配 Harness 文献库，找不到时导入一份副本。源文件路径与论文的对应关系会保留，因此保存 PDF 批注后仍使用原来的对话。模型、会话、渲染、阅读提示词和主题由 Harness 管理；侧栏宽度和显示状态仍由 PDFlight 在窗口之间同步。按 **Shift-Command-A** 可隐藏或显示侧栏。

打开论文时，连接插件会把可转换的 PDFlight 旧文本对话导入 Harness 原生会话。含图片附件或格式不受支持的记录保留在 `~/Library/Application Support/dev.pdflight.reader/ai-chats`，侧栏会提示；原始文件不会删除。嵌入面板使用 WebKit 并连接正在运行的 Harness，因此内存占用与旧版原生侧栏不同。

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
