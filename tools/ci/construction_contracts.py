"""Small source checks for the migrated construction APIs; runtime parity remains a separate check."""
import re
from pathlib import Path


def inspect(path, source):
    errors = []
    for number, line in enumerate(source.splitlines(), 1):
        code = line.split('#', 1)[0].strip()
        if path.name != 'world.gd' and re.search(r'\bGrass\.scatter\s*\(', code):
            errors.append(f'{path}:{number}: use await world.scatter_grass so construction can yield')
        # These calls can now yield when Game opts into scheduled construction.
        if re.search(r'\b(?:BgForest\.build|Battlegrounds\.build|\w+\._scatter_ferns)\s*\(', code) and not re.search(r'\bawait\b', code):
            errors.append(f'{path}:{number}: await the scheduled builder before activation')
    return errors


def check(root=Path('scripts')):
    return [error for path in root.rglob('*.gd') for error in inspect(path, path.read_text())]


if __name__ == '__main__':
    errors = check()
    for error in errors:
        print(error)
    raise SystemExit(1 if errors else 0)
