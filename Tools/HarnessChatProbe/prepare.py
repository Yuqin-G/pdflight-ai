#!/usr/bin/env python3
"""Prepare an isolated, local-only Harness/WebKit feasibility experiment."""

import argparse
import json
import os
import struct
from pathlib import Path


class Asar:
    def __init__(self, path):
        self.file = path.open('rb')
        _, header_size, _, json_size = struct.unpack('<IIII', self.file.read(16))
        self.base = 8 + header_size
        self.header = json.loads(self.file.read(json_size))

    def node(self, path):
        node = self.header
        for part in path.strip('/').split('/'):
            node = node['files'][part]
        return node

    def extract_tree(self, path, target):
        def extract(node, out):
            if 'files' in node:
                out.mkdir(parents=True, exist_ok=True)
                for name, child in node['files'].items():
                    extract(child, out / name)
            elif 'offset' in node:
                out.parent.mkdir(parents=True, exist_ok=True)
                self.file.seek(self.base + int(node['offset']))
                out.write_bytes(self.file.read(node['size']))
            else:
                raise ValueError(f'Unsupported unpacked or linked ASAR entry: {out.name}')
        extract(self.node(path), target)

    def read_text(self, path):
        node = self.node(path)
        self.file.seek(self.base + int(node['offset']))
        return self.file.read(node['size']).decode('utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--harness', type=Path, default=Path('/Applications/DeepSeek Harness.app'))
    parser.add_argument('--source', type=Path, default=Path.home() / 'Documents/deepseek-harness/default-workspace')
    parser.add_argument('--history', type=Path, help='local native-migration chat JSON; never uploaded')
    parser.add_argument('--output', type=Path, required=True, help='new private output directory outside the repository')
    args = parser.parse_args()
    target = args.output.resolve()
    repo = Path(__file__).resolve().parents[2]
    if target == repo or repo in target.parents:
        parser.error('output must be outside the repository; it may contain private chat data')
    target.mkdir(mode=0o700, parents=True, exist_ok=False)
    archive = Asar(args.harness / 'Contents/Resources/app.asar')
    base = 'dsh/node_modules/@deepseek-ai/'
    archive.extract_tree(base + 'dsh-web-frontend/dist/assets', target / 'assets')
    scripts = list((target / 'assets').glob('index-*.js'))
    if len(scripts) != 1:
        raise ValueError('Expected exactly one Harness index script')
    original = scripts[0].read_text()
    marker = 'const Ls=globalThis.dshDesktopBoot,'
    if original.count(marker) != 1:
        raise ValueError('Unsupported Harness boot bundle')
    (target / 'assets/pdflight-static.js').write_text(original.split(marker)[0] + '\nglobalThis.__PD_STATIC__=OZ();\n')
    exports = {
        'chat': 'exports.PDLocale=zh;exports.PDComponent=AssistantMarkdown;exports.PDChatView=ChatView;exports.PDChatFlow=ChatFlow;exports.PDUser=UserMessageNodeView;exports.PDAssistant=AssistantNodeView;exports.PDUserContent=UserContent;exports.PDActions=MessageIconActions;',
        'conversation': 'exports.PDLocale=zh;exports.PDComponent=InputBar;exports.PDShell=SessionInputShell;exports.PDUserText=UserText;exports.PDContent=ConversationContent;exports.PDViews=DefaultConversationViews;',
        'model-selection': 'exports.PDLocale=zh;exports.PDComponent=ModelSelect;',
    }
    for name, public in exports.items():
        package = 'dsh-client-ui-' + name
        source = archive.read_text(base + package + '/lib/client.js')
        if name == 'conversation':
            # Harness trims the user's prompt before its sink. Preserve exactly
            # what was typed, as required by the PDFlight integration.
            for expression in ('draft', 'out'):
                before = f'defaultSink({expression}.trim(), attachmentIds, mode, attempt.signal)'
                after = f'defaultSink({expression}, attachmentIds, mode, attempt.signal)'
                if source.count(before) != 1:
                    raise ValueError('Unsupported Harness input serialization')
                source = source.replace(before, after)
        if source.count('return module.exports') != 1:
            raise ValueError(f'Unsupported {package} module')
        (target / (package + '.js')).write_text(source.replace('return module.exports', public + 'return module.exports'))
    styles = args.source / 'dsh-src/packages/client/ui-theme/src/styles'
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        (target / name).write_bytes((args.source / 'dsh-src' / name).read_bytes())
    for name in ('design-platform.css', 'base.css', 'gradient-shadow-text.css', 'scrollbar.css'):
        (target / name).write_bytes((styles / name).read_bytes())
    reader = (args.source / 'pdf-reading-mode/client.js').read_text()
    css_start = '    const css = `'
    if reader.count(css_start) != 1:
        raise ValueError('Unsupported PDF reading mode CSS source')
    (target / 'pdf-reading.css').write_text(
        reader.split(css_start, 1)[1].split('\n`;', 1)[0]
        + reader.split('    const refinedCss = `', 1)[1].split('\n`;', 1)[0]
    )
    plugin_entry = "    return {inject:['slots','locale','layout','sessions','resources'],apply(ctx) {"
    if reader.count(plugin_entry) != 1:
        raise ValueError('Unsupported PDF reading mode plugin')
    reader = reader.replace(plugin_entry, "    globalThis.__PDReading = {ConversationTabs, paperLabel, dictionaries};\n" + plugin_entry)
    (target / 'pdf-reading-client.js').write_text(reader)
    css_files = {}
    for prefix in ('index', 'vendor'):
        matches = list((target / 'assets').glob(prefix + '-*.css'))
        if len(matches) != 1:
            raise ValueError(f'Expected exactly one {prefix} CSS file')
        css_files[prefix] = matches[0].name
    here = Path(__file__).resolve().parent
    html = (here / 'probe.html').read_text()
    for key, value in css_files.items():
        html = html.replace('__' + key.upper() + '_CSS__', value)
    (target / 'probe.html').write_text(html)
    (target / 'probe.js').write_bytes((here / 'probe.js').read_bytes())
    (target / 'full-probe.html').write_text(html.replace('src="probe.js"', 'src="full-probe.js"'))
    (target / 'full-probe.js').write_bytes((here / 'full-probe.js').read_bytes())
    (target / 'harness-chat-zoom.js').write_bytes((repo / 'Resources/HarnessChat/harness-chat-zoom.js').read_bytes())
    composer = (here / 'composer.html').read_text()
    for key, value in css_files.items():
        composer = composer.replace('__' + key.upper() + '_CSS__', value)
    (target / 'composer.html').write_text(composer)
    (target / 'composer.js').write_bytes((here / 'composer.js').read_bytes())
    if args.history:
        history = json.loads(args.history.read_text())
        conversations = history['conversations']
        active = history.get('activeConversationID')
        matches = [c for c in conversations if c.get('id') == active]
        selected = matches[0] if matches else conversations[0]
        messages = selected['messages']
    else:
        messages = [{'id': 'synthetic-user', 'role': 'user', 'content': '测试', 'createdAt': '2026-01-01T00:00:00Z'},
                    {'id': 'synthetic-assistant', 'role': 'assistant', 'content': 'Markdown 和公式：$E=mc^2$', 'createdAt': '2026-01-01T00:00:01Z'}]
    data = 'window.__TEST_MESSAGES__=' + json.dumps(messages, ensure_ascii=True) + ';\n'
    fd = os.open(target / 'test-history.js', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(data)
    print(f'Prepared local-only probe with {len(messages)} messages at {target}')


if __name__ == '__main__':
    main()
