#!/usr/bin/env python3
"""설치 직후 스킬 구조·frontmatter 검증."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = [
    "SKILL.md",
    "scripts/install.sh",
    "scripts/setup-credentials.sh",
    "scripts/cartier_auto.py",
    "scripts/cartier_auto/__init__.py",
    "scripts/cartier_auto/_common.py",
    "scripts/cartier_auto/monitor.py",
    "scripts/cartier_auto/runner.py",
    "scripts/cartier_auto/purchaser.py",
    "scripts/cartier_auto/site.py",
    "scripts/cartier_auto/cli.py",
    "scripts/cartier_auto/credentials.py",
    "scripts/cartier_auto/config.py",
    "scripts/tests/test_cartier_auto.py",
    "scripts/run.sh",
    "scripts/quick_validate.py",
]


def main() -> int:
    errors = []
    for rel in EXPECTED:
        if not (ROOT / rel).exists():
            errors.append(f"누락: {rel}")
    skill_md = ROOT / "SKILL.md"
    if skill_md.exists():
        head = skill_md.read_text(encoding="utf-8")[:200]
        if not head.startswith("---"):
            errors.append("SKILL.md frontmatter가 없음")
        if "name: cartier-auto" not in head:
            errors.append("SKILL.md name 필드 오류")
    # Python import 스모크 테스트
    sys.path.insert(0, str(ROOT / "scripts"))
    try:
        from cartier_auto import cli, monitor, site  # noqa
    except Exception as exc:
        errors.append(f"파이썬 import 실패: {exc}")
    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    print("OK cartier-auto 구조·frontmatter 검증 통과")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
