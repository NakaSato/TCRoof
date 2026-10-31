#!/usr/bin/env python3
"""Validate vendored skill integrity, discovery aliases, and local skill links."""

import hashlib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    result = hashlib.sha256()
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for item in files:
        name = item.name if path.is_file() else item.relative_to(path).as_posix()
        result.update(name.encode() + b"\0" + item.read_bytes() + b"\0")
    return result.hexdigest()


def main():
    lock = json.loads((ROOT / ".agents/skills/sources.lock.json").read_text())
    errors = []
    names = list(lock["localSkills"])
    for source in lock["sources"]:
        path = ROOT / source["path"]
        if not path.exists():
            errors.append(f"Missing source: {source['path']}")
            continue
        if digest(path) != source["sha256"]:
            errors.append(f"Source hash changed: {source['path']}; review before refreshing the lock")
        if not (ROOT / source["license"]).is_file():
            errors.append(f"Missing license: {source['license']}")
        if path.is_dir():
            names.append(source["name"])
    for name in names:
        skill = ROOT / ".agents/skills" / name / "SKILL.md"
        if not skill.is_file():
            errors.append(f"Missing skill: {name}")
            continue
        text = skill.read_text()
        if not text.startswith("---\n") or f"\nname: {name}\n" not in text:
            errors.append(f"Invalid skill frontmatter/name: {name}")
        alias = ROOT / ".claude/skills" / name
        if not alias.is_symlink() or alias.resolve() != skill.parent.resolve():
            errors.append(f"Missing or incorrect Claude alias: {name}")

    # Project-owned Markdown links should resolve locally. Upstream code snippets can
    # intentionally contain example paths; their integrity is checked by the hashes.
    owned = [ROOT / ".agents/skills/README.md"] + [
        ROOT / ".agents/skills" / name / "SKILL.md" for name in lock["localSkills"]
    ]
    for path in owned:
        for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", path.read_text()):
            if "://" not in target and not target.startswith("#"):
                destination = path.parent / target.split("#", 1)[0]
                if not destination.exists():
                    errors.append(f"Broken link in {path.relative_to(ROOT)}: {target}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Verified {len(names)} skills, Claude aliases, {len(lock['sources'])} source hashes, and licenses.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
