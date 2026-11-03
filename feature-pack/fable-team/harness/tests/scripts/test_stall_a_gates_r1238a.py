"""r1238 단계 A — ft-stall-scan [stall a] «지금 spawn» 경보의 전제 게이트 2개 (카드 «단계 A r4 · r4b» 동결 반례).

게이트 1(카드 흐름 상한): a 후보 팀마다 처리 단계 첫 일로 ft-card-flow.sh --team <팀> --root <루트> --gate 1회(7초 · 판정 기한 밖).
  rc 0 = a 유지 · rc 4 = a 뺌 + «a 보류» 1줄 · rc 3·그 밖·시간 초과 = a 뺌 + «a? … 확인 실패(rc N)» 1줄 · 팀 env 의 FT_CARD_FLOW=0·FT_CARD_CAP=0 = 부르지 않음(a 유지).
게이트 2(배정 원장): ready 카드마다 <루트>/.fable-team/state/card-assign/<카드>.json — waiting 사람·면제대기 = 계속 뺌 · 그 밖 사유 = now − max(updated, 마지막 a 재촉) < 2시간이면 뺌 ·
  꼴 위반·읽기 실패·updated 미래 = 그 팀 a 0 + «a? 대기 카드 판정 불가» 1줄 · a_card_nudged 는 stall-scan.json 에 저장 · 발신 성공(rc 0)만 기록.

R1238A_BIN = 시험할 bin 폴더(기본 kit) — 변이(mutate_stall_a_r1238a.py)와 기준판 대조가 이 env 로 다른 bin 을 건다.
실 tmux·실 쪽지·실 루트 0 · 임시 루트 · 자기 재호출 0 · 고정 sleep 0(스텁 지연은 «호출 안» 에서만).
카드 반례 이름 대응: S-cap1·S-cap5(rc 4) · S-cap2 · S-cap3'' · S-cap6 · S-cap4 · S-wait1'·S-wait11·S-wait5''·S-wait10'·S-wait12 · S-rep1 · S-wait7·S-wait8·S-wait9 ·
S-dl3 · S-pen1 · S-st1·S-st2·S-st3 · S-snd1 · S-fut1·S-fut2.
S-rep1 의 사유 «부하» 는 판정 3914 로 대기 사유에서 폐지돼 «석» 으로 갈음(옛 «부하» 원장 행은 S-leg1 = 배정 없음으로 셈).
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1238A_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
GIT = shutil.which("git") or "git"
GENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "LC_ALL": "C"}
H = 3600
M = "t1-master#1"


@pytest.fixture
def w(tmp_path: Path) -> World:
    world = World(tmp_path)
    world.cards("t1", ["c1"])
    world.state(M, "IDLE", 5)
    world.mail("planner#1", 3, 20, frm=M, body="발주 확인")  # 우편함 실재 + [정리] 아님 → 팀장 심박 «없음» = 같은 스캔의 f 경보 1(a 갈래와 독립인지 대조용)
    return world


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    w.state(M, "IDLE", 5 - (int(w.env["FT_NOW"]) - NOW) / 60)  # advance 뒤에도 master 는 «지금 − 5분» 부터 IDLE(iso 는 NOW 기준 분)
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=60)


def dry(w: World) -> subprocess.CompletedProcess[str]:
    return scan(w, "--dry-run")


def ledger(w: World, stem: str, raw: str | None = None, **kw: object) -> None:
    d = w.root / ".fable-team/state/card-assign"
    d.mkdir(parents=True, exist_ok=True)
    _ = (d / f"{stem}.json").write_text(raw if raw is not None else json.dumps(kw), encoding="utf-8")


def waiting(w: World, stem: str, reason: str, age_s: float) -> None:
    ledger(w, stem, state="waiting", reason=reason, since=NOW - age_s, updated=NOW - age_s, urgent=False)


def put_state(w: World, **doc: object) -> Path:
    p = w.root / ".fable-team/state/stall-scan.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text(json.dumps(doc), encoding="utf-8")
    return p


def saved(w: World) -> dict:
    return json.loads((w.root / ".fable-team/state/stall-scan.json").read_text(encoding="utf-8"))


def team_env(w: World, text: str) -> None:
    p = w.root / ".fable-team/bin-t1/t1-env.sh"
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text(text, encoding="utf-8")
    cap = w.stub / "cap.py"
    _ = cap.write_text("import sys\nsys.exit(0)\n")
    w.env["FT_SEAT_CAP_PY"] = str(cap)  # 팀 env 가 있으면 ft_seat_cap 이 불린다 — 스텁(rc 0 = 여유)


def lines(out: str, needle: str) -> list[str]:
    return [x for x in out.splitlines() if needle in x]


def flow_calls(w: World) -> list[str]:
    return w.calls("flow.calls")


# ── 게이트 1: 카드 흐름 상한 ─────────────────────────────────────────────
def test_s_cap1_s_cap5_gate_rc4_removes_a_with_one_hold_line_even_without_team_env(w: World) -> None:
    assert not (w.root / ".fable-team/bin-t1").exists()  # S-cap5 — 팀 env 없는 팀(v65 꼴)도 gate 는 돈다
    w.flow_rc(4)
    r = dry(w)
    c = counts(r.stdout)
    assert c["a"] == "0", r.stdout
    assert len(lines(r.stdout, "a 보류 t1 — 카드 상한(card-flow rc 4)")) == 1, r.stdout
    calls = flow_calls(w)
    assert len(calls) == 1 and calls[0].endswith(f"--team t1 --root {w.root} --gate"), calls  # 스텁 계약: 인자 검증은 스텁이(다르면 rc 2 «args»)


def test_s_cap2_gate_rc0_keeps_a(w: World) -> None:
    r = dry(w)
    assert counts(r.stdout)["a"] == "1" and "대기 카드 1장(c1)" in r.stdout and "a 보류" not in r.stdout and "a?" not in r.stdout, r.stdout
    assert len(flow_calls(w)) == 1


def test_s_cap3_gate_rc3_removes_a_with_one_failure_line(w: World) -> None:
    w.flow_rc(3)
    r = dry(w)
    assert counts(r.stdout)["a"] == "0" and len(lines(r.stdout, "a? t1 카드 상한 확인 실패(rc 3) — a 0")) == 1, r.stdout


def test_s_cap6_gate_over_7s_is_rc124_failure_and_other_branches_stay(w: World) -> None:
    _ = (w.stub / "flow.sleep").write_text("7.5")  # 감시기 호출 상한 7초를 넘김(지연 1회)
    r = dry(w)
    c = counts(r.stdout)
    assert c["a"] == "0" and len(lines(r.stdout, "a? t1 카드 상한 확인 실패(rc 124) — a 0")) == 1, r.stdout
    assert c["f"] == "1", r.stdout  # 같은 스캔의 팀장 심박 경보(f)는 그대로


def test_s_cap4_team_env_switch_off_skips_gate_and_keeps_a(w: World) -> None:
    w.flow_rc(4)
    for sw in ("FT_CARD_CAP", "FT_CARD_FLOW"):
        team_env(w, f"export {sw}=0\n")
        r = dry(w)
        assert counts(r.stdout)["a"] == "1" and "a 보류" not in r.stdout, (sw, r.stdout)
        assert flow_calls(w) == [], (sw, flow_calls(w))  # gate 호출 0


def test_s_cap7_team_env_without_switch_still_gates(w: World) -> None:
    team_env(w, "export UNRELATED=1\n")
    w.flow_rc(4)
    r = dry(w)
    assert counts(r.stdout)["a"] == "0" and len(flow_calls(w)) == 1, r.stdout


# ── 게이트 2: 배정 원장 ──────────────────────────────────────────────────
@pytest.mark.parametrize("reason", ["사람", "면제대기"])
def test_s_wait1_s_wait11_human_reasons_stay_out_for_good_and_gate_is_not_called(w: World, reason: str) -> None:
    waiting(w, "c1", reason, 5 * H)
    r = dry(w)
    assert counts(r.stdout)["a"] == "0", r.stdout
    assert flow_calls(w) == [], flow_calls(w)  # 후보가 먼저 줄어 gate 를 안 부른다


def test_s_wait5_other_reason_older_than_2h_is_candidate_again(w: World) -> None:
    waiting(w, "c1", "석", 3 * H)
    assert counts(dry(w).stdout)["a"] == "1"


def test_s_wait10_da_reason_3h_old_is_candidate_again(w: World) -> None:
    waiting(w, "c1", "DA", 3 * H)
    assert counts(dry(w).stdout)["a"] == "1"


def test_s_wait12_other_reason_30min_old_stays_out(w: World) -> None:
    waiting(w, "c1", "석", H // 2)
    assert counts(dry(w).stdout)["a"] == "0"


@pytest.mark.parametrize("nudged_ago_s,expect_a", [(H, "0"), (3 * H, "1")])
def test_s_rep1_nudge_record_extends_the_2h_window(w: World, nudged_ago_s: int, expect_a: str) -> None:
    waiting(w, "c1", "석", 5 * H)
    _ = put_state(w, handled={}, prev=[], seats={}, a_card_nudged={"c1": NOW - nudged_ago_s})
    assert counts(dry(w).stdout)["a"] == expect_a


def test_s_leg1_old_load_ledger_row_counts_as_no_assignment(w: World) -> None:
    waiting(w, "c1", "부하", 5 * H)  # 판정 3914 — 옛 «부하» 행은 배정 없음(후보 그대로) · «a?» 로 팀을 영구히 막지 않는다
    r = dry(w)
    assert counts(r.stdout)["a"] == "1" and "a?" not in r.stdout, r.stdout


def test_s_wait_seat_none_and_missing_ledger_are_candidates(w: World) -> None:
    assert counts(dry(w).stdout)["a"] == "1"  # S-wait4 — 원장 없음
    for state in ("seat", "none"):
        ledger(w, "c1", state=state, seat="x", updated=NOW - 60)
        assert counts(dry(w).stdout)["a"] == "1", state


BAD_LEDGERS = {
    "null": "null", "list": "[]", "empty-object": "{}", "bad-json": "{",
    "state-x": json.dumps({"state": "x", "updated": NOW}),
    "reason-y": json.dumps({"state": "waiting", "reason": "y", "updated": NOW - 5 * H}),
    "no-updated": json.dumps({"state": "waiting", "reason": "석"}),
}


@pytest.mark.parametrize("name", sorted(BAD_LEDGERS))
def test_s_wait7_broken_ledger_is_team_a0_plus_one_undecided_line(w: World, name: str) -> None:
    ledger(w, "c1", raw=BAD_LEDGERS[name])
    r = dry(w)
    assert counts(r.stdout)["a"] == "0" and len(lines(r.stdout, "a? t1 대기 카드 판정 불가")) == 1, (name, r.stdout)


def test_s_wait8_one_ok_card_plus_one_broken_ledger_is_whole_team_a0(w: World) -> None:
    w.cards("t1", ["c2"])
    ledger(w, "c2", raw="[]")
    r = dry(w)
    assert counts(r.stdout)["a"] == "0" and len(lines(r.stdout, "a? t1 대기 카드 판정 불가")) == 1, r.stdout


def gitrepo(w: World) -> None:
    """S-wait9 — 카드 체크아웃을 git 리포(ref 길)로 바꾼다: origin/main 에 c1 이 있다."""
    wt = w.root / ".worktrees/wt-t1"
    origin = w.root / ".worktrees/origin-t1.git"
    for args, cwd in ((["init", "-q", "--bare", "-b", "main", str(origin)], wt.parent), (["init", "-q", "-b", "main"], wt), (["remote", "add", "origin", str(origin)], wt),
                      (["add", "-A"], wt), (["commit", "-q", "-m", "c"], wt), (["push", "-q", "origin", "main"], wt)):
        r = subprocess.run([GIT, *args], cwd=cwd, env=GENV, capture_output=True, text=True, timeout=30)
        assert r.returncode == 0, (args, r.stderr)


@pytest.mark.parametrize("via", ["disk", "ref"])
def test_s_wait9_same_rule_on_both_card_read_paths(w: World, via: str) -> None:
    if via == "ref":
        gitrepo(w)
    waiting(w, "c1", "사람", 5 * H)
    assert counts(dry(w).stdout)["a"] == "0", via
    waiting(w, "c1", "석", 3 * H)
    assert counts(dry(w).stdout)["a"] == "1", via


# ── 판정 기한 · 펜털티 ───────────────────────────────────────────────────
def test_s_dl3_gate_runs_after_judge_phase_so_slow_gate_cannot_trip_the_deadline(w: World) -> None:
    lint = w.stub / "slow-lint.sh"
    _ = lint.write_text('#!/bin/sh\nsleep 6\nexit 0\n')  # 앞 판정 ≈ 6초(대기 카드 lint 1회)
    lint.chmod(0o755)
    w.env["FT_INDEX_LINT"] = str(lint)
    w.env["FT_STALL_SCAN_TOTAL_S"] = "10"
    _ = (w.stub / "flow.sleep").write_text("4")  # gate 4초 — 판정 안에서 불렸다면 6+4 > 10−1 로 기한 초과
    r = dry(w)
    assert r.returncode == 0 and "판정 기한" not in r.stdout, (r.returncode, r.stdout)
    c = counts(r.stdout)
    assert c["a"] == "1" and c["f"] == "1", r.stdout  # 같은 스캔 f 경보 그대로
    assert len(flow_calls(w)) == 1


def test_s_pen1_gate_removed_a_is_not_penalty_material(w: World) -> None:
    put_state(w, handled={M: NOW - 1200}, prev=[f"a:{M}"], seats={})  # 직전 스캔에 같은 master a 가 처리됨
    w.flow_rc(4)
    r = scan(w)
    assert counts(r.stdout)["a"] == "0", r.stdout
    assert "penalty-on" not in "\n".join(w.scan_log()), w.scan_log()
    assert M not in saved(w)["handled"] or saved(w)["handled"][M] == NOW - 1200  # gate 로 뺀 a 는 handled 기록 0


def test_s_pen1_control_same_setup_with_gate_pass_does_turn_penalty_on(w: World) -> None:
    put_state(w, handled={M: NOW - 1200}, prev=[f"a:{M}"], seats={})
    scan(w)
    assert "penalty-on" in "\n".join(w.scan_log()), w.scan_log()  # 양성 대조 — 이 시험이 penalty-on 을 «볼 수 있다»


# ── 저장 · 발신 · 미래 값 (r4b) ──────────────────────────────────────────
def test_s_st1_nudge_record_survives_a_new_process(w: World) -> None:
    ledger(w, "c1", state="none", since=NOW - 5 * H, updated=NOW - 5 * H)  # 배정 없음 = 후보 → 실행 1 이 a 를 보낸다
    sent = scan(w)
    assert counts(sent.stdout)["a"] == "1" and any("[stall a]" in x for x in w.mbox_log()), sent.stdout
    assert saved(w)["a_card_nudged"] == {"c1": NOW}
    waiting(w, "c1", "석", 5 * H)  # 그 뒤 사유 석으로 기록(updated 5시간 전)
    w.advance(600)  # 새 프로세스 실행 2 (10분 뒤)
    again = dry(w)
    assert counts(again.stdout)["a"] == "0", again.stdout  # 재촉 기록 복원 → 마지막 재촉 뒤 2시간 창


def test_s_st2_old_state_file_without_field_or_with_wrong_type_is_empty(w: World) -> None:
    for doc in ({"handled": {}, "prev": [], "seats": {}}, {"handled": {}, "prev": [], "seats": {}, "a_card_nudged": []},
                {"handled": {}, "prev": [], "seats": {}, "a_card_nudged": {"c1": "x", "c2": True}}):
        _ = put_state(w, **doc)
        r = scan(w)
        assert r.returncode == 0 and "Traceback" not in r.stderr + r.stdout and counts(r.stdout)["a"] == "1", (doc, r.stdout, r.stderr)
        assert isinstance(saved(w)["a_card_nudged"], dict)


def test_s_st3_record_is_kept_when_card_is_out_of_candidates_this_scan(w: World) -> None:
    team_env(w, "")
    _ = (w.stub / "cap.py").write_text("import sys\nprint('REJECT 팀 상한')\nsys.exit(1)\n")  # ft_seat_cap full → 후보 밖
    _ = put_state(w, handled={}, prev=[], seats={}, a_card_nudged={"c1": NOW - H})
    r = scan(w)
    assert counts(r.stdout)["a"] == "0", r.stdout
    assert saved(w)["a_card_nudged"] == {"c1": NOW - H}


def test_s_st4_record_older_than_2h_is_dropped_on_save(w: World) -> None:
    waiting(w, "c1", "사람", 5 * H)
    _ = put_state(w, handled={}, prev=[], seats={}, a_card_nudged={"c1": NOW - 3 * H, "c2": NOW - H})
    _ = scan(w)
    assert saved(w)["a_card_nudged"] == {"c2": NOW - H}


def test_s_snd1_failed_send_leaves_no_handled_no_nudge_and_next_scan_retries(w: World) -> None:
    bad = w.stub / "mbox-fail.sh"
    _ = bad.write_text('#!/bin/sh\ncase "$1" in send) exit 3;; esac\nexit 0\n')
    bad.chmod(0o755)
    w.env["FT_MBOX_SH"] = str(bad)
    ledger(w, "c1", state="none", since=NOW - 5 * H, updated=NOW - 5 * H)
    r = scan(w)
    assert counts(r.stdout)["a"] == "1", r.stdout
    doc = saved(w)
    assert M not in doc["handled"] and doc.get("a_card_nudged") == {}, doc
    assert any("a 발신 실패 rc=3" in x for x in w.scan_log()), w.scan_log()
    waiting(w, "c1", "석", 5 * H)  # 재촉 기록이 남았다면 이 카드는 2시간 창에 걸려 후보 밖 — 기록 0 이므로 다음 스캔에 다시 후보
    w.advance(600)
    assert counts(dry(w).stdout)["a"] == "1"


def test_s_fut1_ledger_updated_in_the_future_is_team_a0_with_one_line(w: World) -> None:
    waiting(w, "c1", "석", -24 * H)  # updated = now + 24h
    r = dry(w)
    assert counts(r.stdout)["a"] == "0" and len(lines(r.stdout, "a? t1 대기 카드 판정 불가 — updated 미래 c1")) == 1, r.stdout


def test_s_fut2_future_nudge_record_is_dropped_with_one_line_and_a_stays(w: World) -> None:
    waiting(w, "c1", "석", 5 * H)
    _ = put_state(w, handled={}, prev=[], seats={}, a_card_nudged={"c1": NOW + 24 * H})
    r = dry(w)
    assert counts(r.stdout)["a"] == "1" and len(lines(r.stdout, "재촉 기록 미래 값 버림 c1")) == 1, r.stdout
