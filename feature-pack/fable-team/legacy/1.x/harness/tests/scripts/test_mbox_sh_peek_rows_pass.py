"""r2183(카드 mbox-peek-rows-pass) — mbox.sh peek 이 `--rows` 를 mbox.py 로 넘긴다 · 모르는 인자는 rc 2.

keeper_settle.py 가 부르는 입구는 mbox.sh 다(`bash mbox.sh peek <좌석> --rows`). 그런데 mbox.sh 의
peek 갈래는 첫 인자만 넘겨서 `--rows` 가 조용히 버려졌고, keeper 는 행을 못 받아 미읽음 1통이라도 있으면
끝난 좌석을 붙잡았다(2.0.70 설치 뒤 harness 두 좌석 실측).

계약: Q1 `peek <me> --rows` = `python3 mbox.py peek <me> --rows` 와 stdout 바이트·rc 같음 ·
Q2 인자 없는 `peek <me>` = 지금 글자 그대로 · Q3 모르는 인자 = rc 2 · stdout 0줄 · usage 1줄 ·
Q4 좌석은 첫 인자(`peek --rows <좌석>` = rc 2) · Q6 recv 갈래의 PENDING-AFTER 그대로.

격리: 가짜 쪽지함(FT_MBOX_DIR)·가짜 명부(FT_SEATS_JSON)·상태 폴더(FT_MBOX_STATE_DIR)만 쓴다 ·
실 우편함 0 · tmux 0 · 네트워크 0 · sleep 0 · 사례마다 70초 안. 자기 재호출 0.
변이 M92·M93 은 tmp 사본에서만(R8658_MBOX_SH 로 시험할 파일을 덮는다).
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

HARNESS = Path(__file__).resolve().parents[2]
MBOX_SH = Path(os.environ.get("R8658_MBOX_SH") or HARNESS / "comm" / "mbox.sh")
MBOX_PY = MBOX_SH.parent / "mbox.py"
SEAT, PEER = "byz-t-harness-nano-rows#0", "byz-t-harness-master#1"
USAGE = "usage: mbox.sh peek <me> [--rows]"

# 변이 자리 — M92 = `--rows` 를 안 넘김(옛 줄) · M93 = 뒤 인자를 검사 없이 전부 넘김(옛 동작)
M92_OLD = 'if [ "$_pr" = 1 ]; then exec python3 "$MBOXPY" peek "$_pme" --rows; fi'
M92_NEW = 'exec python3 "$MBOXPY" peek "$_pme"'
M93_OLD = (
    '         case "$_pme" in -*) echo "' + USAGE + '" >&2; exit 2 ;; esac\n'
    '         case "$#:${1:-}" in 0:) ;; 1:--rows) _pr=1 ;; *) echo "' + USAGE + '" >&2; exit 2 ;; esac\n'
)
M93_NEW = '         set -- "$_pme" "$@"; exec python3 "$MBOXPY" peek "$@"\n'


# ── 가짜 세계 ────────────────────────────────────────────────────────────────
def _box(tmp: Path) -> dict:
    (tmp / "relay").mkdir(parents=True, exist_ok=True)
    (tmp / "seats.json").write_text(json.dumps({SEAT: {"role": "nano"}, PEER: {"role": "master"}}), encoding="utf-8")
    return {**os.environ, "FT_MBOX_DIR": str(tmp), "FT_MBOX_RELAY_DIR": str(tmp / "relay"),
            "FT_MBOX_STATE_DIR": str(tmp / "state"), "FT_SEATS_JSON": str(tmp / "seats.json")}


def _send(env: dict, body: str) -> None:
    r = subprocess.run([sys.executable, str(MBOX_PY), "send", SEAT, PEER, body],
                       env=env, capture_output=True, text=True, timeout=70)
    assert r.returncode == 0, r.stdout + r.stderr


def _sh(env: dict, script: Path, *args: str):
    return subprocess.run(["bash", str(script), *args], env=env, capture_output=True, text=True, timeout=70)


def _py(env: dict, *args: str):
    return subprocess.run([sys.executable, str(MBOX_PY), *args], env=env, capture_output=True, text=True, timeout=70)


@pytest.fixture()
def world(tmp_path: Path):
    env = _box(tmp_path)
    _send(env, "[발주] 첫 쪽지")
    _send(env, "[발주] 둘째 쪽지")
    return tmp_path, env


# ── 계약 (㊶가~사) ──────────────────────────────────────────────────────────
def test_ga_rows_passes_through_bytes_equal(world):
    """㊶가 · Q1 — `mbox.sh peek <좌석> --rows` = mbox.py 와 바이트 같음 · JSON 줄의 seq 가 보낸 순서."""
    _tmp, env = world
    sh = _sh(env, MBOX_SH, "peek", SEAT, "--rows")
    py = _py(env, "peek", SEAT, "--rows")
    assert sh.returncode == 0 and py.returncode == 0, sh.stdout + sh.stderr
    assert sh.stdout == py.stdout, sh.stdout + "\n--- py ---\n" + py.stdout
    lines = sh.stdout.splitlines()
    assert len(lines) == 3, sh.stdout                      # 머리줄 + 미읽음 2줄
    assert lines[0].startswith("pending=2 "), lines[0]
    seqs = [json.loads(x)["seq"] for x in lines[1:]]
    assert seqs == sorted(seqs) and len(set(seqs)) == 2, seqs


def test_na_plain_peek_unchanged(world):
    """㊶나 · Q2 — 인자 없는 peek = 머리줄 1줄 · mbox.py plain 출력과 바이트 같음(회귀 고정)."""
    _tmp, env = world
    sh = _sh(env, MBOX_SH, "peek", SEAT)
    py = _py(env, "peek", SEAT)
    assert sh.returncode == 0, sh.stderr
    assert sh.stdout == py.stdout and len(sh.stdout.strip().splitlines()) == 1, sh.stdout


def test_da_rows_with_zero_pending(tmp_path):
    """㊶다 · Q1 — 미읽음 0통 + `--rows` = `pending=0 …` 1줄 · rc 0."""
    env = _box(tmp_path)
    sh = _sh(env, MBOX_SH, "peek", SEAT, "--rows")
    assert sh.returncode == 0, sh.stderr
    assert sh.stdout.startswith("pending=0 ") and len(sh.stdout.strip().splitlines()) == 1, sh.stdout


@pytest.mark.parametrize("args", [
    ("peek", SEAT, "--row"),
    ("peek", SEAT, "x"),
    ("peek", SEAT, "--rows", "x"),
])
def test_ra_unknown_arg_exits_2(world, args):
    """㊶라 · Q3·Q5 — 모르는 인자 = rc 2 · stdout 0줄 · usage 1줄(조용히 버리지 않는다)."""
    _tmp, env = world
    r = _sh(env, MBOX_SH, *args)
    assert r.returncode == 2, (r.returncode, r.stdout, r.stderr)
    assert r.stdout == "", r.stdout
    assert r.stderr.strip() == USAGE, r.stderr


def test_ma_rows_before_seat_exits_2(world):
    """㊶마 · Q4 — 좌석은 첫 인자다 · `peek --rows <좌석>` = rc 2."""
    _tmp, env = world
    r = _sh(env, MBOX_SH, "peek", "--rows", SEAT)
    assert r.returncode == 2, (r.returncode, r.stdout, r.stderr)
    assert r.stdout == "" and r.stderr.strip() == USAGE, r.stdout + r.stderr


def test_ba_recv_pending_after_unchanged(world):
    """㊶바 · Q6 — recv 갈래는 그대로 · 끝 줄 = `PENDING-AFTER <n>`."""
    _tmp, env = world
    r = _sh(env, MBOX_SH, "recv", SEAT)
    assert r.returncode == 0, r.stderr
    last = r.stdout.strip().splitlines()[-1]
    assert last == "PENDING-AFTER 0", r.stdout


def test_sa_rows_does_not_consume(world):
    """㊶사 — `--rows` 는 읽기만 한다 · 그 뒤 plain peek 의 pending 이 2 그대로."""
    _tmp, env = world
    assert _sh(env, MBOX_SH, "peek", SEAT, "--rows").returncode == 0
    again = _sh(env, MBOX_SH, "peek", SEAT)
    assert again.stdout.startswith("pending=2 "), again.stdout


def test_usage_text_mentions_rows():
    """Q5 — 파일 머리 usage 줄의 peek 칸에 `[--rows]` 가 있다."""
    head = MBOX_SH.read_text(encoding="utf-8").splitlines()[:6]
    usage = [x for x in head if "Usage: mbox.sh" in x]
    assert usage and "peek <me> [--rows]" in usage[0], usage


# ── 변이 (tmp 사본에서만) ──────────────────────────────────────────────────
def _mutant(tmp_path: Path, old: str, new: str) -> Path:
    text = MBOX_SH.read_text(encoding="utf-8")
    assert text.count(old) == 1, "변이 자리가 원본에 1곳이어야 한다: " + old[:40]
    d = tmp_path / "mutant"
    shutil.copytree(MBOX_SH.parent, d)   # mbox.py·헬퍼 모듈까지 같이(tmp 사본에서만 돌린다)
    out = d / "mbox.sh"
    out.write_text(text.replace(old, new), encoding="utf-8")
    return out


def test_m92_rows_not_passed_is_caught(tmp_path):
    """M92 — `--rows` 를 안 넘기면(옛 줄) ㊶가 가 FAIL 이어야 한다 = 머리줄 1줄."""
    box = tmp_path / "box"
    box.mkdir()
    env = _box(box)
    _send(env, "[발주] 첫 쪽지")
    _send(env, "[발주] 둘째 쪽지")
    mut = _mutant(tmp_path, M92_OLD, M92_NEW)
    r = _sh(env, mut, "peek", SEAT, "--rows")
    assert r.returncode == 0 and len(r.stdout.strip().splitlines()) == 1, r.stdout


def test_m93_args_passed_unchecked_is_caught(tmp_path):
    """M93 — 뒤 인자를 검사 없이 전부 넘기면(옛 동작) ㊶라·㊶마 가 FAIL 이어야 한다 = rc 0 + 머리줄."""
    box = tmp_path / "box"
    box.mkdir()
    env = _box(box)
    mut = _mutant(tmp_path, M93_OLD, M93_NEW)
    for args in (("peek", SEAT, "--row"), ("peek", SEAT, "x"), ("peek", "--rows", SEAT)):
        r = _sh(env, mut, *args)
        assert r.returncode == 0 and r.stdout.startswith("pending="), (args, r.returncode, r.stdout, r.stderr)
