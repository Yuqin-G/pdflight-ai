# uwa-lite

PDFlight 随附的精简版 [Universal Web API](https://github.com/lumingya/universal-web-api)(AGPL-3.0)。

把本地浏览器中已登录的 AI 网页端(默认 chat.qwen.ai)桥接成 OpenAI 兼容接口,供 PDFlight 的 Ask PDF 使用。相比完整版,去掉了 Web Dashboard、自动更新、Anthropic/Codex 兼容层、命令面板等外围功能,只保留:

- `POST /v1/chat/completions`(含 `conversation_key`/`conversation_title` 会话绑定、`pdf_attachments`)
- `GET /v1/models`、`GET /health`
- 标签页池、工作流引擎、流式解析器、站点选择器配置
- 浏览器自动拉起:`9222` 无响应时自动启动带调试端口的 Chrome;0 target 时自动补空白页

## 运行

```sh
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
APP_PORT=8199 .venv/bin/python main.py
```

PDFlight 在 AI Base URL 指向 loopback 且端口无响应时会自动拉起本服务(查找顺序:`PDFLIGHT_UWA_HOME` → `~/Library/Application Support/dev.pdflight.reader/uwa-lite` → 可执行文件祖先目录的 `Services/uwa-lite` → `~/Applications/uwa-lite`),退出时只关闭自己拉起的进程。

## 关键环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `APP_PORT` | 8199 | 监听端口,PDFlight 按 Base URL 端口传入 |
| `BROWSER_PORT` | 9222 | 受控浏览器调试端口 |
| `BROWSER_PROFILE_DIR` | 完整版 UWA 的 `chrome_profile`(若存在) | 保留登录态 |
| `CONVERSATION_BINDINGS_DB` | 同上复用 | 会话绑定 SQLite,与完整版同格式 |
| `AUTH_ENABLED` | false | lite 默认关闭(仅 loopback) |

## 站点配置

`config/sites.json` 是从完整版复制的工作流/选择器数据。新增站点按同样格式补充即可;`config/parsers.json` 注册流式解析器。

注意:chat.qwen.ai 需要登录态才有独立的 `/c/<id>` 会话 URL;游客态全部落到 `/c/guest`,会话绑定退化为共享。
