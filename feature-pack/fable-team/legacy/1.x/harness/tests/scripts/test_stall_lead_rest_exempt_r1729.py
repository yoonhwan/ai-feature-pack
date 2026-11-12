"""r1729 — 쉬는 팀장의 심박 면제: 마지막 심박 «첫 줄» 에 쉼 표식이 있고 그 뒤 사건이 0 이면 [멈춤] 0.

계약: A1 쉼 표식 = 심박 첫 줄의 `[다음 없음]` 또는 `막힘 = 사람 답(<10>.<6>)` · A2 사건 = 그 팀장이 오간 쪽지(발신 ft-stall-scan 제외) · 사건이 있으면 첫 사건부터 다시 센다 ·
A3 면제 상한 FT_LEAD_REST_MAX_MIN(기본 240분) · A4 읽기 규칙 그대로(깨진 줄·7초 예산 = 판정 불가) · A5 그 밖 팀장 판정은 지금과 같다.
R1729_BIN = 시험할 bin 폴더(기본 kit) — 변이 사본을 넣어 반대 결과를 대조한다.
⑬ = arch R1 탐침: 표식 없는 팀장도 20분 창 밖 깨진 줄 하나로 u 가 되면 안 된다(면제 0 = 지금 판정 그대로).
"""
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1729_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
REST = "[정리] 한 일 3줄 · [다음 없음]"
PROMOTED = "[HIL] 막힘 보고 · [다음 없음] (원래 [정리])"
BLOCK = "[정리] 한 일 3줄 · 막힘 = 사람 답(1794445218.408129)"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def candidate(w: World) -> None:
    """팀장을 b 후보(경보 후보)로 세우고 다른 좌석은 WORKING — u 칸이 이 카드 판정을 가리지 않게."""
    for seat in ("planner#1", "t1-nano#0"):
        w.state(seat, "WORKING", 0.1)
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


def rest_lead(w: World, minutes: float = 60, body: str = REST, *mails: tuple[str, int, float, str, str]) -> dict[str, str]:
    """후보 + 심박(쉼 표식) + 곁쪽지들 → 스캔 셈. mails = (받는이, seq, 몇 분 전, 보낸이, 본문)."""
    candidate(w)
    w.heartbeat("t1-master#1", minutes, body=body)
    for to, seq, ago, frm, text in mails:
        w.mail(to, seq, ago, frm=frm, body=text)
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=70)
    assert r.returncode == 0, r.stderr
    return counts(r.stdout)


def sends(w: World, to: str) -> list[str]:
    return [x for x in w.mbox_log() if x.startswith(f"send|{to}|")]


def body_of(line: str) -> str:
    return line.split("|")[4]


def log_mail(w: World, to: str, seq: int, minutes_ago: float, frm: str, body: str = "[정리] 한 일 3줄") -> None:
    """recv 뒤 로그로 옮겨진 레코드 — 창(면제 상한) 안이면 판정 대상이다(A4)."""
    ts = datetime.fromtimestamp(int(w.env["FT_NOW"]) - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")
    with open(w.root / ".fable-team/comm/mailbox.log.jsonl", "a", encoding="utf-8") as f:
        _ = f.write(json.dumps({"seq": seq, "ts": ts, "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")


# ── ①②③a 쉼 표식(첫 줄) + 사건 0 = 경보 0 ───────────────────────────────────
@pytest.mark.parametrize("body", [REST, PROMOTED, BLOCK], ids=["①", "②", "③a"])
def test_rest_mark_is_exempt(w: World, body: str) -> None:
    c = rest_lead(w, 60, body)
    assert c["f"] == "0" and c["b"] == "0" and c["u"] == "0", c
    assert not w.mbox_log()


@pytest.mark.parametrize("body", ["[정리] 한 일 3줄 · 막힘 = 사람 답", "[정리] 한 일 3줄\n[다음 없음]"], ids=["③b ts 없는 막힘", "④ 둘째 줄 표식"])
def test_r3b_r4_not_a_rest_mark(w: World, body: str) -> None:  # ③b · ④ 표식이 아니면 지금 판정 그대로
    assert rest_lead(w, 60, body)["f"] == "1"
    assert len(sends(w, "t1-master#1")) == 1


def test_r5_rest_message_from_nano_is_not_a_heartbeat(w: World) -> None:  # ⑤ 보낸이가 현역 팀장이 아니다
    candidate(w)
    w.heartbeat("t1-nano#0", 60, body=REST)
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=70)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert "심박 없음" in body_of(sends(w, "t1-master#1")[0])


# ── ⑥⑦⑧⑨ «그 뒤 사건» 이 면제를 깬다(스캐너 [멈춤]·옛 번호는 규칙 그대로) ──────────
def test_r6a_order_after_rest_25min_is_alert(w: World) -> None:  # ⑥ 사건 25분 → 경보 1
    c = rest_lead(w, 60, REST, ("t1-master#1", 771, 25, "planner#1", "발주 — 카드 확인"))
    assert c["f"] == "1", c
    assert len(sends(w, "t1-master#1")) == 1


def test_r6b_order_after_rest_10min_is_quiet(w: World) -> None:  # ⑥ 사건 10분 → 경보 0
    c = rest_lead(w, 60, REST, ("t1-master#1", 772, 10, "planner#1", "발주 — 카드 확인"))
    assert c["f"] == "0", c
    assert not w.mbox_log()


def test_r7_lead_sent_order_after_rest_is_an_event(w: World) -> None:  # ⑦ 보낸이가 그 팀장인 쪽지도 사건
    assert rest_lead(w, 60, REST, ("t1-nano#0", 773, 25, "t1-master#1", "발주 — 이어서 하세요"))["f"] == "1"
    assert len(sends(w, "t1-master#1")) == 1


def test_r8_stall_scan_notice_is_not_an_event(w: World) -> None:  # ⑧ 스캐너 [멈춤] 만(25분 전) = 사건 0
    c = rest_lead(w, 60, REST, ("t1-master#1", 774, 25, "ft-stall-scan", "[멈춤] t1-master#1 팀장 심박 60분"))
    assert c["f"] == "0", c
    assert not w.mbox_log()


def test_r9_old_seat_number_counts_as_event(w: World) -> None:  # ⑨ 옛 번호(t1-master#0) = role_key 같음
    assert rest_lead(w, 60, REST, ("t1-master#0", 775, 25, "planner#1", "발주 — 카드 확인"))["f"] == "1"
    assert len(sends(w, "t1-master#1")) == 1


# ── ⑩ 면제 상한 240분 ───────────────────────────────────────────────────────
def test_r10a_rest_over_cap_is_alert(w: World) -> None:  # ⑩ 241분 → 경보 1
    assert rest_lead(w, 241, REST)["f"] == "1"
    assert len(sends(w, "t1-master#1")) == 1


def test_r10b_rest_under_cap_is_quiet(w: World) -> None:  # ⑩ 239분 → 경보 0
    c = rest_lead(w, 239, REST)
    assert c["f"] == "0" and c["u"] == "0", c
    assert not w.mbox_log()


# ── ⑪⑬ 창 밖 깨진 줄·미래 ts = 면제 0 · 처리 0 ──────────────────────────────
@pytest.mark.parametrize("body", [REST, "[정리] 한 일 3줄"], ids=["⑪a 쉼 표식", "⑬ 표식 없음"])
def test_r11a_old_broken_line_outside_window_is_not_exempt(w: World, body: str) -> None:
    """깨진 줄이 20분 창 밖(240분 안)에 있으면 쉼 로그만 판정 불가 → 면제 0 = 지금 판정 그대로(경보 1 · u 0).
    표식 없는 팀장도 같다(A5 · arch R1 탐침 = ⑬) — 진짜 멈춤을 u 칸으로 가리지 않는다."""
    with open(w.root / ".fable-team/comm/mailbox.log.jsonl", "a", encoding="utf-8") as f:
        _ = f.write("{ 깨진 줄\n")  # 파일 앞(오래된 자리) — 끝에서 읽는 20분 창은 이 줄에 닿지 않는다
    log_mail(w, "planner#1", 7, 60, frm="x", body="발주")  # 창 밖(20분 밖 · 240분 안)
    c = rest_lead(w, 60, body)
    assert c["f"] == "1" and c["u"] == "0", c
    assert len(sends(w, "t1-master#1")) == 1


def test_r11b_future_rest_heartbeat_is_not_fresh(w: World) -> None:  # ⑪ 미래 ts 쉼 심박 = 판정 불가
    c = rest_lead(w, -120, REST)
    assert c["u"] == "1" and c["f"] == "0", c
    assert not w.mbox_log()


# ── ⑫ 표식 없는 팀장 판정은 지금과 같다 ─────────────────────────────────────
def test_r12a_plain_heartbeat_over_20min_is_alert(w: World) -> None:  # ⑫ 25분
    assert rest_lead(w, 25, "[정리] 한 일 3줄")["f"] == "1"
    assert len(sends(w, "t1-master#1")) == 1


def test_r12b_plain_heartbeat_within_20min_is_quiet(w: World) -> None:  # ⑫ 10분
    c = rest_lead(w, 10, "[정리] 한 일 3줄")
    assert c["f"] == "0", c
    assert not w.mbox_log()
