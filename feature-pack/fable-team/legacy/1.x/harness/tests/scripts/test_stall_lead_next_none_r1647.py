"""r1647 — ft-stall-scan f([멈춤]): «닫기 대기 팀장»(마지막 발신 [다음 없음] + 받을 일 0)은 0통, 문구에서 크론 요구 제거.

ⓐ 닫기 대기 = 0통 + 요약 노트 1줄 · ⓑ 새 일이 오면 다시 센다 · ⓒ 쪽지에 크론 낱말 0 · ⓓ 그 밖 팀장은 그대로(판정 불가 = 경보 + 노트).
R1647_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 ⓐ~ⓓ FAIL 을 본다). 자기 재호출 0.
"""
import json
import os
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1647_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def bodies(w: World, to: str) -> list[str]:
    return [r.split("|")[4] for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def lead_stall(w: World) -> None:
    """팀장 b 후보(IDLE 5분 · 미래형 선언) + 심박 25분 = f 후보(임계 20분)."""
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")
    w.heartbeat("t1-master#1", 25)


def next_none(w: World, frm: str = "t1-master#1", seq: int = 950) -> None:
    """팀장 마지막 발신 = [다음 없음] (심박 seq 900 보다 뒤 = 마지막).
    r1949 — planner 앞 [다음 없음] 머리는 쉼 심박이라 r1729 가 먼저 면제한다(r1949 ①) → 닫기 대기 길만 보려고 nano 앞(심박 아님)."""
    w.mail("t1-nano#0", seq, 21, frm=frm, body=f"[다음 없음] {frm} · 받을 일 0 · 닫기 대기")


def two_leads(w: World) -> None:
    """명부에 현역 role=master 행 하나 더 — 승계 직후 옛·새 둘 다 현역(r1001 ⓜ 꼴)."""
    p = w.root / ".fable-team/seats-t1.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["t1-master#0"] = {"role": "master"}
    _ = p.write_text(json.dumps(d), encoding="utf-8")
    w.live.append("t1-master#0")
    w._tmux()


def open_work_zero(w: World, teams: tuple[str, ...] = ("t1",)) -> None:
    """ft-seat-open-work 가 rc0(받을 일 0)을 내는 최소 세계 — 카드 폴더만 있고 진행 카드 0."""
    for team in teams:
        (w.root / f"design/{team}/indices/진행").mkdir(parents=True, exist_ok=True)


# ── ⓐ 닫기 대기 팀장 = [멈춤] 0통 + 「보류 f」 노트 1줄 ─────────────────────────
def test_a_closed_wait_lead_gets_zero_notice(w: World) -> None:  # ⓐ
    lead_stall(w)
    next_none(w)
    open_work_zero(w)
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert "보류 f t1 — [다음 없음] · 받을 일 0" in r.stdout, r.stdout
    assert not bodies(w, "t1-master#1"), w.mbox_log()


# ── ⓑ 그 팀장에게 새 일(미처리 쪽지)이 오면 다시 센다 = [멈춤] 1통 ────────────────
def test_b_new_work_makes_it_alert_again(w: World) -> None:  # ⓑ
    lead_stall(w)
    next_none(w)
    open_work_zero(w)
    w.mail("t1-master#1", 40, 1, frm="planner#1", body="발주 — 새 카드 1장")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert len(bodies(w, "t1-master#1")) == 1, w.mbox_log()


# ── ⓒ [멈춤] 쪽지에 크론 요구(CronList·CronCreate·cron=<id>·15분 틱) 0 ─────────
def test_c_notice_has_no_cron_words(w: World) -> None:  # ⓒ (판정 불가 = 경보 그대로 → 문구를 본다)
    lead_stall(w)
    next_none(w)
    _ = scan(w)  # 카드 폴더 없음 = ft-seat-open-work rc3 = 경보 그대로
    s = bodies(w, "t1-master#1")
    assert len(s) == 1, w.mbox_log()
    assert s[0].startswith("[멈춤] t1-master#1 팀장 심박 25분"), s[0]
    assert "정리 1통" in s[0], s[0]
    for word in ("CronList", "CronCreate", "cron=<id>", "15분 틱"):
        assert word not in s[0], (word, s[0])


# ── ⓓ 그 밖 팀장은 그대로 — [다음 없음] 아님이면 받을 일 0 이어도 경보 ────────────
def test_d1_lead_without_next_none_still_alerts(w: World) -> None:  # ⓓ · 변이 M1 검출
    lead_stall(w)  # 마지막 발신 = [정리] (심박)
    open_work_zero(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert len(bodies(w, "t1-master#1")) == 1, w.mbox_log()


def test_d2_open_work_undecidable_keeps_alert_with_note(w: World) -> None:  # ⓓ · 변이 M2 검출
    lead_stall(w)
    next_none(w)
    r = scan(w)  # 카드 폴더 없음 = rc3 판정 불가
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert "받을 일 판정 불가" in r.stdout, r.stdout
    assert len(bodies(w, "t1-master#1")) == 1, w.mbox_log()


# ── P1·P2 — arch HOLD(#283056) 반례: 작은 파일의 «첫 줄» 을 버리면 안 된다 ──────────────
def test_p1_first_queue_line_is_the_latest_mail(w: World) -> None:  # P1
    w.mail("planner#1", 990, 22, frm="t1-master#1", body="[정리] 새 일 착수")  # 큐 첫 줄 = 더 새 발신
    lead_stall(w)
    next_none(w)
    open_work_zero(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout  # 마지막 발신 = 990 → 닫기 대기 아님


def test_p2_single_line_queue_next_none_is_closed_wait(w: World) -> None:  # P2
    lead_stall(w)
    q, lg = w.root / ".fable-team/comm/mailbox.jsonl", w.root / ".fable-team/comm/mailbox.log.jsonl"
    _ = lg.write_text(q.read_text(encoding="utf-8"), encoding="utf-8")  # 심박은 로그로 옮긴다(recv 뒤)
    _ = q.write_text("", encoding="utf-8")
    next_none(w)  # 큐에는 [다음 없음] 1줄(= 첫 줄)
    open_work_zero(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0", r.stdout


# ── DA 1라운드 HOLD(#283136) — 현역 팀장 둘이 모두 닫기 대기여도 «보류» 노트는 1줄 ──
def test_two_live_leads_closed_wait_one_note(w: World) -> None:
    lead_stall(w)
    two_leads(w)
    w.state("t1-master#0", "IDLE", 6)
    w.jsonl("t1-master#0", "지금 착수하겠습니다")
    next_none(w, frm="t1-master#0", seq=990)
    open_work_zero(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert [x for x in r.stdout.splitlines() if x.startswith("보류 f ")] == ["보류 f t1 — [다음 없음] · 받을 일 0"], r.stdout
    assert not bodies(w, "t1-master#0") and not bodies(w, "t1-master#1"), w.mbox_log()


# ── DA 보정 리뷰 HOLD(#283176) — 중복 판정은 «팀» 단위 · 두 팀이면 팀마다 1줄 ─────────
def test_two_teams_closed_wait_one_note_each(w: World) -> None:
    lead_stall(w)
    next_none(w)
    w.team("t2", "t2-master#1", [])  # 두 번째 팀 — 현역 팀장 1명
    w.state("t2-master#1", "IDLE", 6)
    w.jsonl("t2-master#1", "지금 착수하겠습니다")
    w.heartbeat("t2-master#1", 25, seq=901)
    next_none(w, frm="t2-master#1", seq=990)
    open_work_zero(w, ("t1", "t2"))
    r = scan(w)
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert [x for x in r.stdout.splitlines() if x.startswith("보류 f ")] == [
        "보류 f t1 — [다음 없음] · 받을 일 0", "보류 f t2 — [다음 없음] · 받을 일 0"], r.stdout
    assert not w.mbox_log(), w.mbox_log()


# ── bin 과 kit 사본 = 같은 바이트 ─────────────────────────────────────────────
def test_bin_and_kit_same_bytes() -> None:
    harness = Path(__file__).resolve().parents[2]
    assert (harness / "bin/ft_stall_scan.py").read_bytes() == (harness / "kit/fable-team/bin/ft_stall_scan.py").read_bytes()
