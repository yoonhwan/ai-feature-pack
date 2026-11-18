"""r2213 — peek 머리 줄 끝에 « batched=<수> wake=<HH:MM>»(묶음 대기 쪽지 · 확장 ft-mbox-wake.ts check() 와 같은 칸).

r2169 는 감시 쪽지 행에 wake_at 을 달아 확장 좌석을 묶어 깨운다. peek 가 그 칸을 안 보여 planner 가
«쪽지가 쌓였는데 안 깨어남» 으로 오판했다. 계약 O1 같은 규칙 · O2 꼴 · O3 불변 · O4 시계(FT_MBOX_NOW).
격리: 임시 우편함(FT_MBOX_DIR) + 임시 명부 + 합성 행 + 주입 시계 · 실 우편함·실 좌석 0 · sleep 0.
변이는 사본에서만 — R2213_MBOX 로 시험할 mbox.py 를 덮는다.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

MBOX = Path(os.environ.get("R2213_MBOX") or Path(__file__).resolve().parents[2] / "comm" / "mbox.py")
ME, OLD, PEER = "byz-t-arch-pi#20", "byz-t-arch-pi#19", "byz-t-master-claude#1"
NOW = 1_700_000_000


def _hm(epoch):   # 시험 env TZ=UTC 와 같은 시각 글자
    return time.strftime("%H:%M", time.gmtime(epoch))


def _run(box: Path, *args: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay"),
           "FT_SEATS_JSON": str(box / "seats.json"), "FT_ROOTS_TSV": str(box / "no-roots.tsv"),
           "FT_MBOX_NOW": str(NOW), "TZ": "UTC"}
    p = subprocess.run([sys.executable, str(MBOX), *args], env=env, capture_output=True, text=True, timeout=30)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout.splitlines()


def _world(box: Path, rows, wake=True):   # rows = [(seq, to, wake_at | None)] · wake=False = 칸 없는 기준판 꼴
    (box / "seats-t.json").write_text(json.dumps({
        OLD: {"role": "arch", "_replaced_by": ME},
        ME: {"role": "arch", "_replaces": [OLD]},
    }), encoding="utf-8")
    with open(box / "mailbox.jsonl", "w", encoding="utf-8") as f:
        for seq, to, w in rows:
            r = {"seq": seq, "ts": "2026-11-18T03:00:00", "to": to, "from": PEER, "body": "[멈춤] 합성 %d" % seq}
            if wake and w is not None:
                r["wake_at"] = w
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def _pair(tmp_path: Path, rows, *args):   # (wake_at 칸 있는 판, 칸을 뺀 기준판 꼴) peek 줄
    a, b = tmp_path / "a", tmp_path / "b"
    a.mkdir()
    b.mkdir()
    _world(a, rows)
    _world(b, rows, wake=False)
    return _run(a, "peek", ME, *args), _run(b, "peek", ME, *args)


def test_r2_future_two_batched_earliest_wake(tmp_path: Path):   # ② 기준판 Red
    got, base = _pair(tmp_path, [(1, ME, NOW + 600), (2, ME, NOW + 300), (3, ME, None)])
    assert got[0].startswith("pending=3 latest_seq=3 ")
    assert got[0] == base[0] + " batched=2 wake=%s" % _hm(NOW + 300)


def test_r3_past_wake_only_same_as_base(tmp_path: Path):   # ③ 지난 시각 · 지금과 같은 시각 = 묶음 아님
    got, base = _pair(tmp_path, [(1, ME, NOW - 10), (2, ME, NOW)])
    assert got == base and "batched=" not in got[0]


@pytest.mark.parametrize("w", [str(NOW + 10), -5, NOW + 10.5, NOW + 3601, True])
def test_r4_bad_wake_not_batched(tmp_path: Path, w):   # ④ 글자 · 음수 · 소수 · 지금+3600초 넘음 · 참거짓
    got, base = _pair(tmp_path, [(1, ME, w)])
    assert got == base and "batched=" not in got[0]


def test_r4_upper_bound_inclusive(tmp_path: Path):   # ④ 경계 — 지금+3600초 = 묶음(확장 wakeOk <=)
    got, base = _pair(tmp_path, [(1, ME, NOW + 3600)])
    assert got[0] == base[0] + " batched=1 wake=%s" % _hm(NOW + 3600)


def test_r5_eight_unread_no_batched(tmp_path: Path):   # ⑤ 미읽음 8통 = 다 깨움 행(확장 ⓔ)
    got, base = _pair(tmp_path, [(i, ME, NOW + 60 * i) for i in range(1, 9)])
    assert got == base and got[0].startswith("pending=8 ")


def test_r5_seven_unread_batched(tmp_path: Path):   # ⑤ 대조 — 7통은 묶음
    got, base = _pair(tmp_path, [(i, ME, NOW + 60 * i) for i in range(1, 8)])
    assert got[0] == base[0] + " batched=7 wake=%s" % _hm(NOW + 60)


def test_r6_rows_json_unchanged(tmp_path: Path):   # ⑥ --rows JSON 줄 = 기준판 · 머리 줄만 다름
    got, base = _pair(tmp_path, [(1, ME, NOW + 600), (2, ME, None)], "--rows")
    assert got[1:] == base[1:] and len(got) == 3
    assert got[0] == base[0] + " batched=1 wake=%s" % _hm(NOW + 600)


def test_r7_lineage_rows_not_counted(tmp_path: Path):   # ⑦ 승계 직후 — 옛 이름 2통은 pending 에만 · 셈 = 내 이름 6통
    rows = [(1, OLD, NOW + 900), (2, OLD, NOW + 900)] + [(i, ME, NOW + 60 * i) for i in range(3, 9)]
    got, base = _pair(tmp_path, rows)
    assert got[0].startswith("pending=8 ")
    assert got[0] == base[0] + " batched=6 wake=%s" % _hm(NOW + 180)
