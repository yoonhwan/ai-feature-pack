"""r2344 — 심박 로그 읽기가 회전 사본(.1~.3)까지 이어 읽는다.

실사건(#354996 · 판정 #355031): mailbox.log.jsonl 이 5MB 에서 5.2MB 짜리로 밀려나 새 파일이 시작되면,
회전 직후 «창 안» 심박은 전부 `.1` 에 있다. 지금 읽기(#ⓧ1 ft_stall_detect.py _read_mailbox_log)는
지금 로그 한 파일만 끝에서 읽고 파일 앞머리에 닿으면 창이 남아도 끝나므로, 제때 틱을 보낸 desk·팀장에게
거짓 «desk 틱 끊김 240분» [긴급]·[멈춤] 이 나갔다(실제 나이 4.5분).

계약(카드 G1~G5)
- G1 읽는 곳: 지금 로그 → 사본 `.1` → `.2` → `.3`(FT_MBOX_LOG_KEEP · 기본 3 · 있는 것만)
- G2 읽는 법: 파일마다 «끝에서» · 사슬 순서대로 새것→옛것 · 창 밖 줄을 만나면 그 자리에서 멈추고 사본을 열지 않는다
- G3 판정 그대로: _hb_line·is_hb·창 길이·깨진 줄·문구는 손 0
- G4 시간: 예산(t0·budget)은 사슬 전체에서 «하나»(큐와 공유)
- G5 손: 부르는 곳(lead_heartbeat 20분 창 · lead_rest_state 상한 창 · desk_alert 240분 창) 판정이 함께 바뀐다

R2344_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 반례 ⓐ 를 본다). 자기 재호출 0.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2344_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
sys.path.insert(0, str(BIN))
from ft_stall_detect import _read_mailbox_log, desk_alert, lead_heartbeat, lead_rest_state  # noqa: E402

LEAD = "t1-master#1"  # 팀장(심박 발신자)
TO = "planner#1"  # 받는이 role=master
LOGREL = ".fable-team/comm/mailbox.log.jsonl"
FILL_BYTES = 5 * 1024 * 1024  # 파일 하나 = ft-mbox.py SENT_LOG_MAX_BYTES
BROKEN = '{"seq": 999, "ts": "깨진 줄"}'  # ts 파싱 실패 = 깨진 줄(읽으면 broken 에 1 이 붙는다)


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def comm(w: World) -> Path:
    return w.root / ".fable-team/comm"


def _ts(minutes_ago: float) -> str:
    return datetime.fromtimestamp(NOW - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")


def row(to: str, seq: int, minutes_ago: float, frm: str = "x#1", body: str = "발주") -> str:
    return json.dumps({"seq": seq, "ts": _ts(minutes_ago), "to": to, "from": frm, "body": body}, ensure_ascii=False)


def put(w: World, suffix: str, *lines: str) -> Path:
    """로그 사슬에 줄을 적는다 — suffix "" = 지금 로그 · ".1"~".3" = 회전 사본(ft-mbox.py _rotate_sent_log 와 같은 이름)."""
    path = Path(f"{w.root / LOGREL}{suffix}")
    with open(path, "a", encoding="utf-8") as f:
        for line in lines:
            _ = f.write(line + "\n")
    return path


def hb(seq: int, minutes_ago: float, to: str = TO, frm: str = LEAD, body: str = "[정리] 한 일 3줄") -> str:
    return row(to, seq, minutes_ago, frm=frm, body=body)


def fill(w: World, suffix: str, heartbeat: str | None = None) -> None:
    """파일 하나를 5MB(ft-mbox.py SENT_LOG_MAX_BYTES) 채움 줄로 채운다 · 꼬리에 심박 1줄(카드 ⑨ «20MB 사슬»)."""
    line = row(TO, 0, 1, frm="x#1", body="발주 " + "가" * 20) + "\n"
    path = Path(f"{w.root / LOGREL}{suffix}")
    with open(path, "a", encoding="utf-8") as f:
        _ = f.write(line * (FILL_BYTES // len(line.encode())))
        if heartbeat:
            _ = f.write(heartbeat + "\n")


def read(w: World, window: float = 20.0, budget: float = 7.0) -> tuple[str, float | None, int, int]:
    """판정 함수 1회 직접 호출 — (에러, 최신 심박 ts, 깨진 줄, 줄 수). 읽은 «줄 수» 가 사슬 증거다."""
    return _read_mailbox_log(w.root / LOGREL, {LEAD}, {TO}, NOW, window, budget, time.monotonic(), None)


def minutes(stamp: float | None) -> float | None:
    return None if stamp is None else round((NOW - stamp) / 60, 1)


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def candidate(w: World) -> None:
    """팀장을 경보 후보로 — IDLE 5분 + 마지막 글이 미래형 선언(도구 0) · 다른 좌석은 WORKING(u 칸 0)."""
    for seat in ("planner#1", "t1-nano#0"):
        w.state(seat, "WORKING", 0.1)
    w.state(LEAD, "IDLE", 5)
    w.jsonl(LEAD, "확인했습니다. 지금 착수하겠습니다")


def queue(w: World) -> None:
    """안 읽은 큐 1줄 — 큐 파일이 없으면 판정 불가(ERROR)라 심박 판정을 못 본다(r1143 R3 과 같은 이유)."""
    w.mail(TO, 1, 1, frm="x#1", body="발주")


def desk_roster(w: World, rows: dict[str, dict[str, str]]) -> None:
    """desk 명부 — 실사건 발신자 desk#2 (r1143 과 같은 꼴)."""
    _ = (w.root / ".fable-team/seats-desk.json").write_text(
        json.dumps({"_label": "desk", "_master": "desk#2", "_cards": "design/desk/indices", "_cards_wt": "wt-desk", **rows}), encoding="utf-8")
    (w.root / ".worktrees/wt-desk/design/desk/indices").mkdir(parents=True, exist_ok=True)
    w._team_row("desk")


# ── ① G1 — 회전 직후: 창 안 심박이 .1 에만 있어도 읽는다 ──────────────────────
def test_1_heartbeat_only_in_first_slice(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))  # 지금 로그 = 창 안 «심박 아님» 줄뿐(방금 회전)
    put(w, ".1", row(TO, 3, 25), hb(2, 4))  # 위 = 25분(창 밖) · 꼬리 = 4분 심박
    assert read(w) == ("", NOW - 240, 0, 3)  # ts = 4분 전(n = 지금 로그 1 + 사본 2)
    state, ts, why = lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)
    assert (state, why) == ("ok", "") and minutes(ts) == 4.0


# ── ② G5 — ① 세계에서 scan 이 거짓 [멈춤] 을 보내지 않는다 ─────────────────────
def test_2_scan_has_no_false_stall_after_rotation(w: World) -> None:
    candidate(w)
    w.mail("planner#1", 1, 1, frm="x#1", body="발주")  # 큐는 있다(없으면 판정 불가)
    put(w, "", row(TO, 2, 2))
    put(w, ".1", row(TO, 4, 25), hb(3, 4))
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert not sends(w, LEAD)


# ── ③ G2 — 창 밖 줄을 만나면 그 자리에서 멈춘다: 사본을 열지 않는다 ─────────────
def test_3_window_outside_in_current_log_does_not_open_slice(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 30), hb(2, 5))  # 꼬리 = 5분 심박 · 앞 = 30분 창 밖 → 거기서 멈춤
    put(w, ".1", hb(3, 1), BROKEN)  # 열면 ts=1분 · 깨진 줄 1 이 된다
    assert read(w) == ("", NOW - 300, 0, 2)
    assert minutes(lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)[1]) == 5.0


# ── ④ G2 — 사슬을 이어 읽어도 «가장 새» 심박이 이긴다(읽기 순서·최댓값 그대로) ──
def test_4_newest_heartbeat_wins_across_chain(w: World) -> None:
    put(w, "", hb(1, 2), hb(2, 3))
    put(w, ".1", row(TO, 4, 25), hb(3, 4))
    err, ts, broken, _n = read(w)
    assert (err, broken) == ("", 0) and minutes(ts) == 2.0


# ── ⑤ G1 — 사본 번호를 건너뛴다: .1 없음 · .2 있음 → .2 에서 찾는다 ─────────────
def test_5_missing_slice_number_is_skipped(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))
    put(w, ".2", row(TO, 2, 29), hb(3, 7))  # .1 은 없다(있는 것만 · 메모 2)
    assert read(w) == ("", NOW - 420, 0, 3)
    assert minutes(lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)[1]) == 7.0


# ── ⑥ G1 — 로그도 사본도 없음 = 큐만 본다(판정 불가 아님) ──────────────────────
def test_6_no_log_no_slices_is_queue_only(w: World) -> None:
    queue(w)
    assert read(w) == ("", None, 0, 0)
    assert lead_heartbeat(comm(w), {LEAD}, {TO}, NOW) == ("ok", None, "")  # r1143: 창 안 0 ≠ 한 번도 안 보냄


# ── ⑦ G1 — 지금 로그가 없어도(회전 틈) .1 을 본다 ─────────────────────────────
def test_7_missing_current_log_still_reads_slice(w: World) -> None:
    queue(w)
    put(w, ".1", row(TO, 1, 25), hb(2, 4))  # log 는 만들지 않는다(replace 뒤 open 전 틈)
    assert read(w) == ("", NOW - 240, 0, 2)
    assert minutes(lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)[1]) == 4.0


# ── ⑧ G3 — 사본 창 안 깨진 줄 = 판정 불가(ERROR) · 글자는 log 에 둘 때와 같다 ────
def test_8_broken_line_in_slice_is_undecidable(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))
    put(w, ".1", row(TO, 2, 30), BROKEN, hb(3, 5))
    err, ts, broken, _n = read(w)
    assert (err, minutes(ts), broken) == ("", 5.0, 1)
    assert lead_heartbeat(comm(w), {LEAD}, {TO}, NOW) == ("ERROR", None, "쪽지 깨진 줄 1개 — 심박 판정 불가")


# ── ⑨ G4 — 20MB 사슬(5MB × 4) 창 안 전부 읽기 = 예산(7초) 안 · ERROR 0 ─────────
def test_9_twenty_megabyte_chain_within_budget(w: World) -> None:
    queue(w)
    for suffix in ("", ".1", ".2", ".3"):
        fill(w, suffix, hb(1, 0.5) if suffix == "" else None)  # 심박 = 가장 새 줄(지금 로그 꼬리)
    started = time.monotonic()
    err, ts, broken, n = read(w)
    assert (err, broken) == ("", 0) and minutes(ts) == 0.5 and n > 100_000  # 사슬 4벌을 다 읽었다(정확한 초·줄 수는 보고에 적는다)
    print(f"r2344 ⑨ 20MB 사슬 읽기 {time.monotonic() - started:.2f}초 · {n}줄")


# ── ⑩a G5 — 부르는 곳 2: desk 심박(240분 창) · 실사건 그대로 ────────────────────
def test_10a_desk_tick_in_slice_is_fresh(w: World) -> None:
    queue(w)
    desk_roster(w, {"desk#2": {"role": "desk"}})
    put(w, "", row("planner#1", 1, 1))
    put(w, ".1", row("planner#1", 3, 300), row("planner#1", 2, 4, frm="desk#2", body="[완료] desk 틱 05:23 · 잔여 0"))
    alert, age, _ts, undec = desk_alert(w.root, comm(w), "desk#2", "planner#1", NOW)
    assert (alert, undec) == (False, False) and age == 4.0  # 19:24:51 회전 → 19:25:29 scan · 실제 나이 4.5분


# ── ⑩b G5 — 부르는 곳 3: 쉼 면제(상한 창)도 사본의 쉼 심박을 본다 → 경보 0 ─────
def test_10b_rest_exempt_in_slice_stops_stall(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))
    put(w, ".1", row(TO, 3, 400), hb(2, 60, body="[정리] 한 일 3줄 · [다음 없음]"))
    state, rest, first_ev, _hb, first_work = lead_rest_state(comm(w), {LEAD}, {TO}, NOW)
    assert (state, minutes(rest), first_ev, first_work) == ("ok", 60.0, None, None)


# ── ⑪ G3 — 큐(아직 recv 전)에 더 새 심박이 있으면 큐가 이긴다 ──────────────────
def test_11_queue_newer_heartbeat_wins(w: World) -> None:
    put(w, "", row(TO, 1, 3))
    put(w, ".1", row(TO, 2, 25), hb(3, 5))
    w.mail(TO, 4, 1, frm=LEAD, body="[정리] 큐에 남은 더 새 심박")
    state, ts, why = lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)
    assert (state, why) == ("ok", "") and minutes(ts) == 1.0


# ── 덤1 G1 — .1 이 있고 .2 에만 심박 ────────────────────────────────────────
def test_e1_second_slice_when_first_exists(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))
    put(w, ".1", row(TO, 3, 6), row(TO, 2, 4))  # 창 안 · 심박 아님 → 사슬 계속
    put(w, ".2", row(TO, 5, 29), hb(4, 7))
    assert minutes(lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)[1]) == 7.0
    assert read(w)[3] == 5  # 지금 로그 1 + .1 2 + .2 2


# ── 덤2 G1 — 사슬 끝(.3)까지 간다 ───────────────────────────────────────────
def test_e2_third_slice(w: World) -> None:
    queue(w)
    for suffix, seq, ago in (("", 1, 3), (".1", 2, 4), (".2", 3, 5)):
        put(w, suffix, row(TO, seq, ago))
    put(w, ".3", row(TO, 5, 31), hb(4, 8))
    assert minutes(lead_heartbeat(comm(w), {LEAD}, {TO}, NOW)[1]) == 8.0
    assert read(w)[3] == 5


# ── 덤3 G3 — 사본까지 읽어도 심박 판정(_hb_line·발신·받는이·머리)은 그대로 ──────
def test_e3_slice_lines_judged_by_same_rule(w: World) -> None:
    queue(w)
    put(w, "", row(TO, 1, 3))
    put(w, ".1",
        row(TO, 5, 29),  # 창 밖(멈춤) — 파일 위 = 옛 줄
        row(TO, 4, 6, frm=LEAD, body="발주 — 머리 [정리] 아님"),
        hb(3, 5, to="x#1"),  # 받는이가 master/planner 역할 아님
        hb(2, 4, frm="desk#2"))  # 현역 팀장 발신 아님
    err, ts, broken, _n = read(w)  # 줄 수는 안 본다 — 사본을 «안 열어도» 판정은 같다(G3)
    assert (err, ts, broken) == ("", None, 0)
    assert lead_heartbeat(comm(w), {LEAD}, {TO}, NOW) == ("ok", None, "")


# ── 덤4 G4 — 예산은 사슬에서도 하나(줄 256 자리에서 그대로 멈춘다) ─────────────
def test_e4_budget_is_shared_across_chain(w: World) -> None:
    put(w, "", *[row(TO, i, 1) for i in range(300)])
    put(w, ".1", hb(999, 2))
    err, ts, _broken, n = read(w, budget=1e-9)
    assert err.startswith("심박 읽기") and ts is None and n == 256


# ── 덤5 G3 — 창 길이는 그대로: 19.9분은 심박 · 20.1분에서 멈추고 사본은 안 연다 ──
def test_e5_window_length_unchanged(w: World) -> None:
    put(w, "", row(TO, 1, 20.1), hb(2, 19.9))
    put(w, ".1", hb(3, 25), BROKEN)  # 열면 깨진 줄 1 · 창 밖 심박
    assert read(w) == ("", NOW - 1194, 0, 2)
