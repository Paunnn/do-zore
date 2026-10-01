"""Regenerate immutable Godot data and central string catalog from /data.

UI text is edited only in client/localization/strings.json. Keys prefixed data.
are regenerated from the owned-by-backend data sources. Standard library only.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def build():
    target = ROOT / 'client' / 'data'
    target.mkdir(parents=True, exist_ok=True)
    data = {}
    for path in sorted((ROOT / 'data').glob('*.json')):
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        value.pop('$schema', None)
        if path.stem == 'economy':
            data['economy'] = value
        else:
            data.update(value)
    canonical = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    digest = hashlib.sha256(canonical.encode()).hexdigest()
    write(target / 'bundle.json', {'version_hash': digest, 'data': data})
    schemas = {p.name: json.loads(p.read_text(encoding='utf-8-sig'))
               for p in sorted((ROOT / 'contracts' / 'schemas').glob('*.json'))}
    write(target / 'schemas.json', schemas)
    catalog = ROOT / 'client' / 'localization' / 'strings.json'
    strings = json.loads(catalog.read_text(encoding='utf-8-sig')) if catalog.exists() else {}
    strings = {k: v for k, v in strings.items() if not k.startswith('data.')}

    def collect(value, key='data'):
        if isinstance(value, dict):
            if 'sr' in value:
                strings[key] = {'sr': value['sr'], 'en': value.get('en', '')}
            else:
                for field, child in value.items():
                    collect(child, f'{key}.{field}')
        elif isinstance(value, list):
            for i, child in enumerate(value):
                name = child.get('id', i) if isinstance(child, dict) else i
                collect(child, f'{key}.{name}')

    collect(data)
    write(catalog, strings)
    print(f'Bundled {len(data)} collections; {len(strings)} strings; SHA-256 {digest}')


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    build()
