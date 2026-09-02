#!/usr/bin/env python3
"""cartier-auto 실행 진입점 (설치 스킬의 venv로 실행)."""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cartier_auto.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
