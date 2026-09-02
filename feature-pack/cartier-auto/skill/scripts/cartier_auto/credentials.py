#!/usr/bin/env python3
"""자격증명 저장·검증 (설정기는 setup-credentials.sh)."""

from __future__ import annotations

import os
from pathlib import Path

from ._common import CRED_FILE, REQUIRED_CREDS


def quote(value: str) -> str:
    if value and any(c in value for c in " \\\"'#$&()*;<>?[]`|~"):
        return "'" + value.replace("'", "'\\''") + "'"
    return value


def save_credentials_env(values: dict, target: Path | None = None) -> Path:
    """디렉터리 0700, 파일 0600, 원자적 저장."""
    target = target or CRED_FILE
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lines = [
        "# cartier-auto 자격증명 (수동 편집 가능)",
        "",
    ]
    for key in REQUIRED_CREDS:
        raw = values.get(key)
        item = "" if raw is None else str(raw)
        lines.append(f"{key}={quote(item)}")
    body = "\n".join(lines) + "\n"
    tmp = target.with_suffix(".tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.chmod(0o600)
    tmp.replace(target)
    os.chmod(target, 0o600)
    return target
