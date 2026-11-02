#!/usr/bin/env python3
"""Prepare an independent reference using installed Harness components only."""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from prepare import Asar


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--harness', type=Path, default=Path('/Applications/DeepSeek Harness.app'))
    parser.add_argument('--source', type=Path, default=Path.home() / 'Documents/deepseek-harness/default-workspace')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    target = args.output.resolve()
    target.mkdir(parents=True, exist_ok=False)
    archive = Asar(args.harness / 'Contents/Resources/app.asar')
    base = 'dsh/node_modules/@deepseek-ai/'
    archive.extract_tree(base + 'dsh-web-frontend/dist/assets', target / 'assets')
    script, = (target / 'assets').glob('index-*.js')
    original = script.read_text()
    marker = 'const Ls=globalThis.dshDesktopBoot,'
    assert original.count(marker) == 1, 'Unsupported Harness runtime'
    (target / 'assets/pdflight-static.js').write_text(original.split(marker)[0] + '\nglobalThis.__PD_STATIC__=OZ();\n')
    exports = {
        'chat': 'exports.ChatView=ChatView;exports.ChatFlow=ChatFlow;exports.User=UserMessageNodeView;exports.Assistant=AssistantNodeView;exports.UserContent=UserContent;exports.locale=zh;',
        'conversation': 'exports.Content=ConversationContent;exports.Views=DefaultConversationViews;exports.UserText=UserText;',
    }
    for name, public in exports.items():
        text = archive.read_text(base + 'dsh-client-ui-' + name + '/lib/client.js')
        assert text.count('return module.exports') == 1
        (target / (name + '.js')).write_text(text.replace('return module.exports', public + 'return module.exports'))
    subprocess.run([sys.executable, str(Path(__file__).with_name('extract-installed-theme.py')),
                    '--archive', str(args.harness / 'Contents/Resources/app.asar'), '--output', str(target)], check=True, capture_output=True)
    reader = (args.source / 'pdf-reading-mode/client.js').read_text()
    css = []
    for name in ('css', 'refinedCss'):
        match = re.search(r'const ' + name + r' = `([\s\S]*?)`;', reader)
        assert match, 'Unsupported reading stylesheet: ' + name
        css.append(match[1])
    (target / 'pdf-reading.css').write_text('\n'.join(css))
    (target / 'warm-theme.js').write_bytes((args.source / 'claude-warm-theme/client.js').read_bytes())
    vendor, = (target / 'assets').glob('vendor-*.css')
    index, = (target / 'assets').glob('index-*.css')
    html = '''<!doctype html><html lang="zh" data-platform="darwin"><head><meta charset="utf-8">
    <link rel="stylesheet" href="assets/VENDOR"><link rel="stylesheet" href="assets/INDEX">
    <link rel="stylesheet" href="base.css"><link rel="stylesheet" href="corner-shape.css">
    <link rel="stylesheet" href="design-platform.css"><link rel="stylesheet" href="focus.css">
    <link rel="stylesheet" href="onboarding.css"><link rel="stylesheet" href="scrollbar.css">
    <link rel="stylesheet" href="gradient-shadow-text.css"><link rel="stylesheet" href="shiki.css">
    <link rel="stylesheet" href="pdf-reading.css">
    <style>html,body,#root{height:100%;margin:0;overflow:hidden}#root{display:flex;flex-direction:column}
    body{--dsh-content-font-size:14px;--dsh-code-font-size:12px}</style></head><body>
    <script>window.__errors=[];addEventListener('error',e=>__errors.push(e.message||'resource'),true);addEventListener('unhandledrejection',e=>__errors.push(String(e.reason)))</script>
    <div id="root"></div><script type="module" src="reference.js"></script></body></html>'''
    (target / 'reference.html').write_text(html.replace('VENDOR', vendor.name).replace('INDEX', index.name))
    (target / 'reference.js').write_bytes(Path(__file__).with_name('reference.js').read_bytes())
    print(target)


if __name__ == '__main__':
    main()
