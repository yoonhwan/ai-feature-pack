"""r1238 단계 B — ft-stall-scan 이 API 장애 중에는 b·d·f 를 보내지 않고 «보류 — API 장애 중(since HH:MM)» 1줄만 남기며, 장애가 끝나면 나이를 «끝 시각» 부터 다시 센다(끝 뒤 15분 유예).

상태 정본 = <루트>/.fable-team/state/api-outage/seats*.json (ft-api-outage 가 틱 데몬마다 1개 · status OK|OUTAGE|RECOVERED · since · released) — 감시기는 읽기만.
R1 OUTAGE → b·d·f 0 + 보류 노트 · R2 OK·released 5분 전 → 경보 0(유예) · R3 OK·released 40분 전 → f 1 · R4 상태 파일 없음 → f 1 · R5 JSON 깨짐 → f 1 + «판정 불가» 노트 · R6 OUTAGE 에도 a 는 그대로.
입력 꼴 넓힘: R1b = seats-cfo.json 만 OUTAGE(나머지 OK) · R2b = RECOVERED · R5b = OUTAGE 인데 mtime 40분 전(데몬 정지 → «오래됨» 노트 + f 1) · B-4 보류분은 ft-penalty 재료가 아님.
R1238B_BIN = 시험할 bin 폴더(기본 kit) — 변이(mutate_stall_scan_outage_hold_r1238.py)와 기준판 대조가 이 env 로 다른 bin 을 건다.
실 tmux·실 쪽지·실 루트 0 · 임시 루트 · 자기 재호출 0 · 고정 sleep 0.
"""
import json
import os
import subprocess
import time
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1238B_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
M, N = "t1-master#1", "t1-nano#0"
MIN = 60


@pytest.fixture
def w(tmp_path: Path) -> World:
    """팀장 심박 30분(f 후보) · nano b(미래형 선언)·d(미읽음 쪽지) 후보 · 대기 카드 없음 → 장애 문이 없으면 b=1 d=1 f=1."""
    world = World(tmp_path)
    world.state(M, "IDLE", 30)
    world.heartbeat(M, 30)
    world.state(N, "IDLE", 30)
    world.jsonl(N, "확인했습니다. 지금 착수하겠습니다")
    world.mail(N, 7, 30)
    return world


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=60)


def dry(w: World) -> subprocess.CompletedProcess[str]:
    return scan(w, "--dry-run")


def outage(w: World, name: str = "seats.json", status: str = "OUTAGE", mtime_ago_min: float = 1, **kw: object) -> Path:
    d = w.root / ".fable-team/state/api-outage"
    d.mkdir(parents=True, exist_ok=True)
    p = d / name
    doc: dict[str, object] = {"status": status, **kw}
    _ = p.write_text(json.dumps(doc), encoding="utf-8")
    os.utime(p, (NOW - mtime_ago_min * MIN, NOW - mtime_ago_min * MIN))
    return p


def hhmm(epoch: float) -> str:
    return time.strftime("%H:%M", time.localtime(epoch))


def lines(out: str, needle: str) -> list[str]:
    return [x for x in out.splitlines() if needle in x]


def base_counts(w: World) -> dict[str, str]:
    return counts(dry(w).stdout)


def test_r0_control_without_outage_state_b_d_f_all_fire(w: World) -> None:
    c = base_counts(w)
    assert (c["b"], c["d"], c["f"]) == ("1", "1", "1"), c  # R4 와 같은 입력 — 상태 파일 없음


def test_r1_outage_holds_b_d_f_with_one_note(w: World) -> None:
    since = NOW - 20 * MIN
    _ = outage(w, since=since)
    r = dry(w)
    c = counts(r.stdout)
    assert (c["b"], c["d"], c["f"]) == ("0", "0", "0"), r.stdout
    note = lines(r.stdout, "보류 — API 장애 중")
    assert len(note) == 1 and f"(since {hhmm(since)})" in note[0] and "b 1 · d 1 · f 1" in note[0], r.stdout


def test_r1_outage_sends_nothing_and_logs_the_evidence_line(w: World) -> None:
    _ = outage(w, since=NOW - 20 * MIN)
    r = scan(w)
    assert r.returncode == 0 and not [x for x in w.mbox_log() if "[멈춤]" in x or "[stall b]" in x or x.startswith("ring|")], w.mbox_log()
    assert w.tmux_log() == [], w.tmux_log()  # 깨우기(Escape) 0
    assert any("보류 — API 장애 중" in x for x in w.scan_log()), w.scan_log()  # 감시기 로그에 증거 줄


def test_r1_control_without_outage_the_same_scan_does_wake_and_send(w: World) -> None:
    r = scan(w)
    assert r.returncode == 0 and any("[멈춤]" in x for x in w.mbox_log()) and w.tmux_log(), (w.mbox_log(), w.tmux_log())  # 양성 대조


def test_r1b_only_one_daemon_file_says_outage(w: World) -> None:
    _ = outage(w, "seats.json", "OK", released=NOW - 3 * 3600)
    _ = outage(w, "seats-cfo.json", since=NOW - 10 * MIN)
    r = dry(w)
    assert counts(r.stdout)["f"] == "0" and len(lines(r.stdout, "보류 — API 장애 중")) == 1, r.stdout


def test_r1c_earliest_since_of_the_outage_files_is_shown(w: World) -> None:
    _ = outage(w, "seats.json", since=NOW - 10 * MIN)
    _ = outage(w, "seats-ops.json", since=NOW - 50 * MIN)
    assert f"(since {hhmm(NOW - 50 * MIN)})" in dry(w).stdout


@pytest.mark.parametrize("status", ["OK", "RECOVERED"])
def test_r2_r2b_recent_release_is_grace_for_b_d_f(w: World, status: str) -> None:
    _ = outage(w, status=status, released=NOW - 5 * MIN)
    r = dry(w)
    c = counts(r.stdout)
    assert (c["b"], c["d"], c["f"]) == ("0", "0", "0"), (status, r.stdout)
    assert len(lines(r.stdout, "유예 — API 장애 끝")) == 1 and "보류 — API 장애 중" not in r.stdout, r.stdout


def test_r3_release_older_than_15min_is_the_normal_rule(w: World) -> None:
    _ = outage(w, status="OK", released=NOW - 40 * MIN)
    r = dry(w)
    assert (counts(r.stdout)["b"], counts(r.stdout)["d"], counts(r.stdout)["f"]) == ("1", "1", "1") and "API 장애" not in r.stdout, r.stdout


@pytest.mark.parametrize("ago_min,f", [(14, "0"), (16, "1")])
def test_r3b_grace_edge_is_the_heartbeat_threshold(w: World, ago_min: int, f: str) -> None:
    _ = outage(w, status="OK", released=NOW - ago_min * MIN)
    assert counts(dry(w).stdout)["f"] == f


def test_r3c_newest_release_among_files_counts(w: World) -> None:
    _ = outage(w, "seats.json", "OK", released=NOW - 3 * 3600)
    _ = outage(w, "seats-cfo.json", "RECOVERED", released=NOW - 4 * MIN)
    assert counts(dry(w).stdout)["f"] == "0"


def test_r4_no_state_folder_is_the_normal_rule(w: World) -> None:
    assert not (w.root / ".fable-team/state/api-outage").exists()
    r = dry(w)
    assert counts(r.stdout)["f"] == "1" and "API 장애" not in r.stdout


def test_r5_broken_json_is_normal_rule_plus_one_undecided_note(w: World) -> None:
    p = outage(w, status="OK")
    _ = p.write_text("{", encoding="utf-8")
    r = dry(w)
    assert counts(r.stdout)["f"] == "1" and len(lines(r.stdout, "장애 상태 판정 불가 seats.json")) == 1, r.stdout


@pytest.mark.parametrize("doc", [{"status": "X"}, {"status": "OUTAGE"}, {"status": "OUTAGE", "since": "x"}, {"status": "OK", "released": "x"}, []])
def test_r5c_wrong_shape_is_undecided_not_a_hold(w: World, doc: object) -> None:
    d = w.root / ".fable-team/state/api-outage"
    d.mkdir(parents=True)
    _ = (d / "seats.json").write_text(json.dumps(doc), encoding="utf-8")
    r = dry(w)
    assert counts(r.stdout)["f"] == "1" and len(lines(r.stdout, "장애 상태 판정 불가 seats.json")) == 1, (doc, r.stdout)


def test_r5b_outage_file_not_touched_for_40min_is_stale_not_a_permanent_hold(w: World) -> None:
    _ = outage(w, since=NOW - 3 * 3600, mtime_ago_min=40)
    r = dry(w)
    assert counts(r.stdout)["f"] == "1" and len(lines(r.stdout, "장애 상태 오래됨 seats.json 40분 — 경보 그대로")) == 1 and "보류 — API 장애" not in r.stdout, r.stdout


def test_r5d_stale_file_is_dropped_but_a_fresh_one_still_decides(w: World) -> None:
    _ = outage(w, "seats-loom.json", since=NOW - 3 * 3600, mtime_ago_min=9000)
    _ = outage(w, "seats.json", since=NOW - 5 * MIN)
    r = dry(w)
    assert counts(r.stdout)["f"] == "0" and f"(since {hhmm(NOW - 5 * MIN)})" in r.stdout and len(lines(r.stdout, "장애 상태 오래됨 seats-loom.json")) == 1, r.stdout


def test_r6_a_branch_is_untouched_by_the_outage(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state(M, "IDLE", 30)
    _ = outage(w, since=NOW - 5 * MIN)
    c = counts(dry(w).stdout)
    assert c["a"] == "1" and c["f"] == "0", c


def test_b4_held_items_are_not_penalty_material(w: World) -> None:
    d = w.root / ".fable-team/state"
    _ = (d / "stall-scan.json").write_text(json.dumps({"handled": {N: NOW - 1200}, "prev": [f"b:{N}", f"d:{N}"], "seats": {}}), encoding="utf-8")
    _ = outage(w, since=NOW - 5 * MIN)
    _ = scan(w)
    assert "penalty-on" not in "\n".join(w.scan_log()), w.scan_log()


def test_b4_control_same_state_without_outage_turns_penalty_on(w: World) -> None:
    d = w.root / ".fable-team/state"
    _ = (d / "stall-scan.json").write_text(json.dumps({"handled": {N: NOW - 1200}, "prev": [f"b:{N}", f"d:{N}"], "seats": {}}), encoding="utf-8")
    _ = scan(w)
    assert "penalty-on" in "\n".join(w.scan_log()), w.scan_log()
