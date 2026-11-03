#!/usr/bin/env python3
"""Checagens estáticas de referências NUI/JSON (sem runtime FiveM)."""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
html = (root / 'html/index.html').read_text()
css = (root / 'html/missions.css').read_text()
js = (root / 'html/missions.js').read_text()
errors = []

# IDs usados pelo missions.js devem existir no index.html
ids = set(re.findall(r"getElementById\('([^']+)'\)", js))
html_ids = set(re.findall(r'id="([^"]+)"', html))
missing = sorted(ids - html_ids)
if missing:
    errors.append('IDs ausentes no index.html: ' + ', '.join(missing))

# Arquivos referenciados no manifest devem existir
manifest = (root / 'fxmanifest.lua').read_text()
referenced = re.findall(r"'((?:html|client|server|shared|tests|data)/[^']+)'", manifest)
for rel in referenced:
    if not (root / rel).exists():
        errors.append('Arquivo do fxmanifest ausente: ' + rel)

# JSON válido
for rel in ('data/mission_history.json', 'data/admin_log.json'):
    try:
        json.loads((root / rel).read_text())
    except Exception as exc:
        errors.append(f'JSON inválido {rel}: {exc}')

# Balanceamento básico de chaves do CSS
if css.count('{') != css.count('}'):
    errors.append('CSS de missões com chaves desbalanceadas')

# Unidade de distância e zona protegida presentes no config
config = (root / 'config.lua').read_text()
if "DistanceUnit = 'NM'" not in config:
    errors.append('Config.Radar.DistanceUnit ausente')
if "shape   = 'polygon'" not in config:
    errors.append('Zona protegida em polígono ausente')
if 'AdminAces' not in config:
    errors.append('ACE administrativa ausente')

if errors:
    for e in errors:
        print(' [FALHA] ' + e)
    sys.exit(1)
print(f' [OK]   {len(ids)} IDs NUI, {len(referenced)} arquivos do manifest, JSON e CSS consistentes')
