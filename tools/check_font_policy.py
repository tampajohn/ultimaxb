#!/usr/bin/env python3
"""Reject substitute typefaces in the game UI; native bridge owns fallback."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
bad = []
for path in (root / 'Sources/UltimaMac').glob('*.swift'):
    if path.name == 'ClassicNativeFont.swift':
        continue  # central missing-asset fallback
    for line, text in enumerate(path.read_text().splitlines(), 1):
        if re.search(r'NSFont\(name:|\.(?:systemFont|boldSystemFont|monospacedSystemFont)\(', text):
            bad.append(f'{path.relative_to(root)}:{line}: {text.strip()}')
if bad:
    raise SystemExit('\n'.join(bad))
print('Game UI font policy passed: no substitute font declarations outside the asset bridge')
