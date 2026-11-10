"""ft2 Slack 계약 사례 재생 검사기 시험 — 기준 1 + 변이 M1~M3 + 비밀값(ⓔ).

원자료(r1501 case-json · slack.html)는 BYZ 리포에서 `git show <sha>:<경로>` 로 읽는다(복사 0 · 쓰기 0).
BYZ 리포 위치 = 환경변수 FT20_BYZ_REPO 또는 기본 후보. 어느 쪽도 없으면 skip(사유를 화면에 남긴다).
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve()
ROOT = HERE.parents[1] / "contracts" / "slack"          # ft2/contracts/slack
CHECK = ROOT / "replay_check.py"
CANDIDATES = [os.environ.get("FT20_BYZ_REPO", ""),
              str(Path.home() / "Project/Agent/BYZ-Work/BYZ-Agents")]


def byz_repo() -> str:
    """원자료 sha 의 slack.html 객체를 `git cat-file` 로 확인한다(작업트리 체크아웃 무관 · 객체 공유)."""
    src = json.loads((ROOT / "cases/01-c1_roundtrip.json").read_text(encoding="utf-8"))["source"]
    spec = f'{src["sha"]}:design/harness/research/ft-2.0/slack.html'
    for c in CANDIDATES:
        if c and (Path(c) / ".git").exists():
            if subprocess.run(["git", "-C", c, "cat-file", "-e", spec],
                              capture_output=True).returncode == 0:
                return c
    return ""


def run(root: Path, byz: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CHECK), "--root", str(root), "--byz", byz],
                          capture_output=True, text=True, timeout=70)


def need() -> str:
    byz = byz_repo()
    if not byz:
        pytest.skip("BYZ 원자료 리포를 못 찾았다 — FT20_BYZ_REPO 를 지정하라(검사기는 rc3 으로 실패한다)")
    return byz


def copy_root(tmp: Path) -> Path:
    dst = tmp / "slack"
    shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns("__pycache__"))
    return dst


def test_baseline_rc0():
    byz = need()
    p = run(ROOT, byz)
    assert p.returncode == 0, p.stdout + p.stderr
    assert "ⓐ 사례 표 21행" in p.stdout
    assert "결과 PASS" in p.stdout
    assert "미시험 2줄" in p.stdout and "계약 밖 사례 3" in p.stdout


def test_m1_expect_value_changed_fails(tmp_path):
    byz = need()
    root = copy_root(tmp_path)
    f = root / "cases/01-c1_roundtrip.json"
    d = json.loads(f.read_text(encoding="utf-8"))
    d["expect"]["observed"]["checks"]["dispatched"] = False      # M1: expect 1칸 바꾸기
    f.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
    p = run(root, byz)
    assert p.returncode == 1, p.stdout
    assert "ⓒ 사례 c1" in p.stdout


def test_m2_contract_mapping_removed_fails(tmp_path):
    byz = need()
    root = copy_root(tmp_path)
    md = (root / "CONTRACT-18.md")
    text = md.read_text(encoding="utf-8")
    assert "| c1, c2, c3 |" in text
    md.write_text(text.replace("| c1, c2, c3 |", "| 미시험 |"), encoding="utf-8")   # M2: 사례 대응 지우기
    p = run(root, byz)
    assert p.returncode == 1, p.stdout
    assert "줄 2: 표시 미시험" in p.stdout
    assert "차이 3" in p.stdout


def test_m3_channel_key_removed_fails(tmp_path):
    byz = need()
    root = copy_root(tmp_path)
    f = root / "cases/09-d1_channel_key.json"
    d = json.loads(f.read_text(encoding="utf-8"))
    d["given"].pop("channel")                                    # M3: 키 3종 중 channel 빼기
    f.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
    p = run(root, byz)
    assert p.returncode == 1, p.stdout
    assert "given 키 channel 없음" in p.stdout


def test_secret_like_token_fails(tmp_path):
    byz = need()
    root = copy_root(tmp_path)
    f = root / "cases/04-c4_ratelimit.json"
    d = json.loads(f.read_text(encoding="utf-8"))
    d["given"]["event"] += " xoxb-0000-not-a-real-token"          # ⓔ: 비밀값 꼴
    f.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
    p = run(root, byz)
    assert p.returncode == 1, p.stdout
    assert "비밀값 꼴" in p.stdout
