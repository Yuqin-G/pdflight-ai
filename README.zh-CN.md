# PDFlight AI

[English](README.md)

轻量 macOS PDF 阅读器，内置论文库和 Ask PDF 对话侧栏。
支持 macOS 14 及以上版本、Apple Silicon。

- PDF 搜索、目录、划线、批注和阅读位置恢复。
- 多级论文分类与多标签页阅读。
- Harness 风格的字体、表格和公式，正文可独立缩放。
- 输入框大小固定，支持 PDF、图片附件及每篇论文独立对话。
- 支持 OpenAI 兼容 API 和已适配的网页聊天服务，凭据保存在本机。

## 下载

从 [GitHub Releases](https://github.com/Yuqin-G/pdflight-ai/releases/latest) 下载，
解压后将 **PDFlight.app** 移到“应用程序”。当前版本使用临时签名；
首次启动如遇系统提示，请按住 Control 点击应用并选择“打开”。

## 构建

安装 Apple Command Line Tools 后运行：

```sh
git clone --recurse-submodules https://github.com/Yuqin-G/pdflight-ai.git
cd pdflight-ai
./Scripts/build-app.sh
open dist/PDFlight.app
```

首次构建会下载并编译 MuPDF。对话渲染资源已随应用打包，显示对话无需
安装 DeepSeek Harness；发送消息前请在应用中配置模型或网页服务。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开 / 保存 | ⌘O / ⌘S |
| 搜索 | ⌘F |
| 划线 / 撤销 | ⌘E / ⌘Z |
| 适合宽度 | ⌘0 |
| 显示 / 隐藏 Ask PDF | ⇧⌘A |

[许可证](LICENSE) · [架构](CONTEXT.md) · [性能测试](BENCHMARK.md)
