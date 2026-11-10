#!/usr/bin/env python3
"""r1086 변이 시험 — 사본을 3가지로 망가뜨려 새 시험이 «빨강» 이 되는지 본다.

완료 조건의 변이 3종: ⓐ «① 짚기 끔»(파일 머리 읽기로 돌아감) · ⓑ «claude 아님 빼기 끔»(pi 좌석도 폴더를 읽음) ·
ⓕ «PYTHONPATH 줄 끔»(검증기가 가드 모듈을 못 봄). 증거 줄은 stdout 에 남긴다.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]  # harness
FAM = H.parent  # fable-team (시험은 PACK = parents[3] = fable-team 을 기준으로 길을 잡는다)
UTIL = "harness/bin/ft_api_outage_util.py"
KIT_UTIL = "harness/kit/fable-team/bin/ft_api_outage_util.py"
MAG = "harness/kit/slack-mirror/magazine_from_news.sh"
TEST = "harness/tests/scripts/test_locate_env_r1086.py"
PY = sys.executable if subprocess.run([sys.executable, "-c", "import pytest"], capture_output=True).returncode == 0 else str(Path.home() / ".venv/bin/python")
IGN = shutil.ignore_patterns(".git", "__pycache__", ".ruff_cache")

MUT = [
    ("ⓐ ① 짚기 끔", [(UTIL, "    if (tree := ps_tree(deadline)) is not None:  # ① 짚기", "    if False:  # ① 짚기"),
                     (KIT_UTIL, "    if (tree := ps_tree(deadline)) is not None:  # ① 짚기", "    if False:  # ① 짚기")]),
    ("ⓑ claude 아님 빼기 끔", [(UTIL, "                nonclaude.add(s)", "                pass"),
                             (KIT_UTIL, "                nonclaude.add(s)", "                pass")]),
    ("ⓕ PYTHONPATH 줄 끔", [(MAG, 'PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" bash "$VERIFY"', 'bash "$VERIFY"')]),
]


def copy_tree(tmp: Path) -> Path:
    """fable-team/bin·kit·tests 만 사본으로 — pytest 가 PACK(=fable-team) 기준으로 길을 잡으므로 그 층이 필요하다."""
    root = tmp / "fable-team"
    for rel in ("harness/bin", "harness/kit", "harness/tests"):
        shutil.copytree(FAM / rel, root / rel, symlinks=True, ignore=IGN)
    subprocess.run(["git", "init", "-q", str(root)], check=True)  # conftest 의 git 가드가 «리포 안» 이기를 요구
    return root


bad = 0
for name, pairs in MUT:
    tmp = Path(tempfile.mkdtemp()) / "h"
    tmp.mkdir()
    root = copy_tree(tmp)
    for rel, old, new in pairs:
        p = root / rel
        t = p.read_text(encoding="utf-8")
        if old not in t:
            print(f"BAD {name}: 자국 없음 {rel} — {old[:60]}")
            bad += 1
            continue
        p.write_text(t.replace(old, new, 1), encoding="utf-8")
    r = subprocess.run([PY, "-m", "pytest", str(root / TEST), "-q"], capture_output=True, text=True, timeout=600, cwd=str(root))
    out = r.stdout + r.stderr
    fail = [ln for ln in out.splitlines() if ln.startswith("FAILED")]
    print(f"변이 {name}: rc={r.returncode} FAILED={len(fail)} {'OK(빨강)' if r.returncode != 0 else 'BAD(초록)'}")
    for ln in fail[:4]:
        print("  " + ln)
    if r.returncode == 0:
        bad += 1
    elif not fail:
        print("  " + "\n  ".join(out.strip().splitlines()[-6:]))  # 수집 오류면 그 줄을 남긴다(«빨강» 이 시험 때문인지 확인)

print(f"변이 결과: {'전부 빨강 OK' if bad == 0 else f'BAD {bad}'}")
sys.exit(0 if bad == 0 else 1)
