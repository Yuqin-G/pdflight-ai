# uwa-lite

PDFlight 随附的精简版 [Universal Web API](https://github.com/lumingya/universal-web-api)(AGPL-3.0)。

把本地浏览器中已登录的 AI 网页端(默认 chat.qwen.ai)桥接成 OpenAI 兼容接口,供 PDFlight 的 Ask PDF 使用。相比完整版,去掉了 Web Dashboard、自动更新、Anthropic/Codex 兼容层、命令面板等外围功能,只保留:

- `POST /v1/chat/completions`(含 `conversation_key`/`conversation_title` 会话绑定、`pdf_attachments`)
- `GET /v1/models`、`GET /health`
- 标签页池、工作流引擎、流式解析器、站点选择器配置
- 浏览器自动拉起:`9222` 无响应时自动启动带调试端口的 Chrome;0 target 时自动补空白页

瘦身方式:命令引擎、tool calling、Arena 直连模型/图像生成、结果事件桥接等模块以
`app/services/` 下的同名 stub 替换(全部探测接口返回"未启用"安全默认值),
`command_engine_actions/_runtime/_results/_storage`、`command_result_store`、
`tool_calling_parse/_prompts/_validation_retry/_common`、`arena_gpt_image_command`、
`arena_proxy_rotation`、`restart_guard` 已删除(约 1.5 万行)。

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

注意:chat.qwen.ai 需要登录态才能稳定开新会话。游客态新开标签页会被重定向到
`/auth`(无输入框,工作流失败);已有 `/c/guest` 标签页可复用但绑定退化为共享。
建议在受控 Chrome 里登录一次 Qwen。


## Native session continuity (Qwen)

`app/` is the imported service source. The optional sibling `api/`, `core/`, and
`services/` trees are old copies and are not imported by `main.py`.

Send the stable client session ID as `conversation_key` on
`POST http://127.0.0.1:8199/v1/chat/completions` with advertised model `qwen`.
`client_session_id`, `clientSessionId`, and `session_id` are equivalent request
aliases. A request without a key keeps its existing independent-request behavior.
The first keyed request opens a dedicated Qwen tab. Later requests with the same
key restore its SQLite-bound website URL and submit only the newest user message.
They do not replay the PDF or conversation transcript. For SDK runtimes that add
technical user-role context after the entered request, mark that context with the
standard OpenAI message field `name: "dsh_context"`; it is excluded from continuation
selection. Entered messages may use `name: "dsh_user"`. Unnamed clients keep their
normal behavior.

Completion JSON and SSE JSON chunks add these top-level fields (outside content):

```json
{
  "conversation_key": "native-session-id",
  "client_session_id": "native-session-id",
  "conversation_id": "actual-qwen-conversation-id",
  "conversation_url": "https://chat.qwen.ai/c/actual-qwen-conversation-id",
  "conversation_state": "continued"
}
```

The first SSE chunk may have null website ID/URL and state `pending` until Qwen
creates its chat. Terminal chunks include the persisted website URL when available.
States are `pending`, `created`, `continued`; lookup reports `bound`. Nonstream
responses also set `X-UWA-Conversation-URL` and `X-UWA-Conversation-ID` when bound.
The request session ID and website conversation ID are distinct identities.

`GET /v1/conversations?client_session_id=native-session-id` (or
`?conversation_key=native-session-id`) retrieves the same binding metadata without
opening a tab. It returns HTTP 404 with detail `conversation_not_bound` until a
durable URL exists, and HTTP 422 for invalid or absent keys. This service uses its
existing authentication settings for both completions and lookup.

Stored and emitted URLs exclude credentials, query strings, and fragments. Guest
threads are not durable bindings. Failed or cancelled browser requests should not
be automatically retried: submission may already have happened on the website.
The Qwen workflow clicks its visible send button, since Enter did not submit on
the tested current Qwen page.

Regression checks (no browser, no credentials, temporary SQLite only):

```sh
.venv/bin/python -m unittest discover -s tests -p 'test_conversation_contract.py'
```
