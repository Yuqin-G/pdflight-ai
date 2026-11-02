#!/usr/bin/env python3
"""Export the installed Harness UI theme's exact ordered CSS literals."""
import argparse
import hashlib
import json
import re
from pathlib import Path

from prepare import Asar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=Path('/Applications/DeepSeek Harness.app/Contents/Resources/app.asar'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='verify existing output without writing')
    args = parser.parse_args()
    archive = Asar(args.archive)
    module_path = 'dsh/node_modules/@deepseek-ai/dsh-client-ui-theme/lib/client.js'
    module = archive.read_text(module_path)
    package = json.loads(archive.read_text('dsh/node_modules/@deepseek-ai/dsh-client-ui-theme/package.json'))
    # Bundled CSS is emitted as JSON-compatible double-quoted JS literals.
    # Parsing the literals avoids running any application or plugin code.
    literals = {}
    for match in re.finditer(r'(?:const|let|var)\s+([\w$]+)\s*=\s*("(?:[^"\\]|\\.)*")', module):
        literals[match[1]] = json.loads(match[2])
    styles_match = re.search(r'const STYLES = \[([\s\S]*?)\n\s*\];', module)
    if not styles_match:
        raise ValueError('Unsupported installed theme STYLES declaration')
    styles = re.findall(r'\["([a-z-]+\.css)",\s*([\w$]+)\]', styles_match[1])
    if len(styles) != 8 or len(set(name for name, _ in styles)) != len(styles):
        raise ValueError('Unsupported or duplicate installed theme stylesheet inventory')
    with args.archive.open('rb') as stream:
        archive_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
    provenance = {'package': package['name'], 'version': package['version'],
                  'archiveSha256': archive_hash, 'modulePath': module_path,
                  'moduleSha256': hashlib.sha256(module.encode()).hexdigest(), 'styles': []}
    if not args.check:
        args.output.mkdir(parents=True, exist_ok=True)
    for name, variable in styles:
        if variable not in literals or not literals[variable]:
            raise ValueError(f'Missing installed CSS literal: {variable}')
        value = literals[variable].encode()
        target = args.output / name
        if args.check:
            if target.read_bytes() != value:
                raise ValueError(f'Bundled stylesheet differs from installed literal: {name}')
        else:
            target.write_bytes(value)
        provenance['styles'].append({'name': name, 'variable': variable, 'bytes': len(value),
                                     'sha256': hashlib.sha256(value).hexdigest()})
    metadata = (json.dumps(provenance, indent=2) + '\n').encode()
    metadata_path = args.output / 'theme-provenance.json'
    if args.check:
        if metadata_path.read_bytes() != metadata:
            raise ValueError('Theme provenance differs from installed archive')
    else:
        metadata_path.write_bytes(metadata)
    print(json.dumps({'mode': 'verified' if args.check else 'written', **provenance}, ensure_ascii=False))


if __name__ == '__main__':
    main()
