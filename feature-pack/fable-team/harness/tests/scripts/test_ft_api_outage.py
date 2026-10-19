"""R146 — API 장애 시작·끝 알림 + 끊긴 좌석 «복구 뒤 1회» 재개 (`ft_api_outage.py`) 시험.

합성 jsonl(실 좌석 기록 복사 0) + 가짜 mbox + 고정 시계(--now)만 쓴다 — 실제 tmux·mbox·~/.claude 조회 0.
"""

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[3] / "harness" / "bin"
MODULE = SCRIPTS / "ft_api_outage.py"
UTIL = SCRIPTS / "ft_api_outage_util.py"
KIT_DIR = Path(__file__).resolve().parents[3] / "harness" / "kit" / "fable-team" / "bin"
KIT_MODULE = Path(__file__).resolve().parents[3] / "harness" / "kit" / "fable-team" / "bin" / "ft_api_outage.py"
SECRET = "SECRET_BODY_MUST_NOT_APPEAR"
T0 = 1_760_400_000  # 고정 시계 기준(초)
PLANNER = "t-planner#1"


def _iso(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _normal(uid: str, epoch: int) -> dict[str, object]:
    return {"type": "assistant", "uuid": uid, "timestamp": _iso(epoch),
            "message": {"model": "claude-sonnet-5-5", "content": [{"type": "text", "text": "ok"}]}}


def _error(uid: str, epoch: int, text: str) -> list[dict[str, object]]:
    err = {"type": "assistant", "uuid": uid, "timestamp": _iso(epoch), "isApiErrorMessage": True,
           "apiErrorStatus": 503, "error": "server_error",
           "message": {"model": "<synthetic>", "content": [{"type": "text", "text": text}]}}
    return [err, {"type": "system", "subtype": "turn_duration", "timestamp": _iso(epoch), "durationMs": 142}]


def _user(uid: str, epoch: int, text: str = "go") -> dict[str, object]:
    return {"type": "user", "uuid": uid, "timestamp": _iso(epoch), "message": {"role": "user", "content": text}}


class Fx:
    """합성 좌석 jsonl + 가짜 mbox + 상태 파일 한 벌."""

    def __init__(self, tmp: Path, script: Path = MODULE, mbox_rc: int = 0, name: str = "api-outage", barrier: bool = False):
        self.tmp, self.script = tmp, script
        self.state = tmp / "state" / f"{name}.json"
        self.log = tmp / "mbox.log"
        self.mbox = tmp / "mbox.sh"
        wait = ""  # 장애 알림 발신 직전 두 프로세스가 «겹치게» 기다린다 — 잠금이 없으면 둘 다 여기 도달한다
        if barrier:
            wait = f'case "$4" in "[API 장애"*) b="{tmp}/barrier"; mkdir -p "$b"; touch "$b/arr.$$"; for _ in $(seq 1 40); do [ "$(ls "$b" | wc -l)" -ge 2 ] && break; sleep 0.05; done;; esac\n'
        self.mbox.write_text(f'#!/bin/bash\n[ "$1" = send ] || exit 9\n{wait}echo "$2|$3|$4" >> "{self.log}"\nexit {mbox_rc}\n', encoding="utf-8")
        self.seats: dict[str, Path] = {}

    def add(self, seat: str, recs: list[dict[str, object]]) -> None:
        p = self.seats.setdefault(seat, self.tmp / f"{seat.replace('#', '_')}.jsonl")
        with p.open("a", encoding="utf-8") as fh:
            fh.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in recs)

    def run(self, now: int, extra: list[str] | None = None) -> subprocess.CompletedProcess[str]:
        stdin = "".join(f"{s}\t{p}\n" for s, p in self.seats.items())
        env = {**os.environ, "TZ": "UTC", "LC_ALL": "C.UTF-8"}
        for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
            env.pop(k, None)
        cmd = [sys.executable, "-I", str(self.script), "--state", str(self.state), "--mbox", str(self.mbox),
               "--notify", PLANNER, "--now", str(now), *(extra or [])]
        return subprocess.run(cmd, input=stdin, capture_output=True, text=True, env=env, timeout=30)

    def calls(self) -> list[tuple[str, ...]]:
        if not self.log.exists():
            return []
        return [tuple(ln.split("|", 2)) for ln in self.log.read_text(encoding="utf-8").splitlines()]

    def to(self, dest: str) -> list[str]:
        return [body for d, _f, body in self.calls() if d == dest]


def _outage_fx(tmp: Path, script: Path = MODULE) -> Fx:
    """기준선 1회 뒤, 좌석 A·B 가 오류로 끊기고 C 는 정상 idle 인 장애 시작 상태."""
    fx = Fx(tmp, script)
    fx.add("t-a#1", [_user("a0", T0 - 900), _normal("a1", T0 - 880)])
    fx.add("t-b#1", [_user("b0", T0 - 900), _normal("b1", T0 - 880)])
    fx.add("t-c#1", [_user("c0", T0 - 900), _normal("c1", T0 - 880)])
    assert fx.run(T0 - 600).returncode == 0
    fx.add("t-a#1", [_user("a2", T0 - 70), *_error("a-err", T0 - 60, f"API Error: 429 rate_limit_error {SECRET}")])
    fx.add("t-b#1", [_user("b2", T0 - 70), *_error("b-err", T0 - 50, f"API Error: 403 OAuth authentication is currently not allowed {SECRET}")])
    return fx


def test_outage_start_notice_once_with_cause_summary(tmp_path):  # 1ⓐ · 1ⓖ
    fx = _outage_fx(tmp_path)
    r = fx.run(T0)
    assert r.returncode == 0, r.stderr
    notes = fx.to(PLANNER)
    assert len(notes) == 1 and notes[0].startswith("[API 장애 시작 ")
    assert "끊긴 좌석 2" in notes[0] and "rate_limit 1" in notes[0] and "oauth_not_allowed 1" in notes[0]
    assert len(fx.calls()) == 1  # 장애 중 재개 0
    assert "사용량 제한 2(rate_limit 1 · oauth_not_allowed 1 · subscription_disabled 0)" in notes[0] and "기타 API 오류 0" in notes[0]  # 판정 1633 ① · arch 보강 ⓗ
    first = time.strftime("%H:%M", time.gmtime(T0 - 60))
    assert f"해제 예상: 미상 · 첫 제한 {first}" in notes[0] and "05:" not in notes[0].split("해제 예상")[1]  # 판정 1633 ② · +5시간 계산 0
    assert SECRET not in notes[0] + r.stdout + r.stderr


def test_unclassified_error_has_no_release_estimate(tmp_path):  # 판정 1633 ② — 제한 문구가 아니면 추정 0
    fx = Fx(tmp_path)
    fx.add("t-a#1", [_user("a0", T0 - 900), _normal("a1", T0 - 880)])
    fx.run(T0 - 600)
    fx.add("t-a#1", [_user("a2", T0 - 70), *_error("a-err", T0 - 60, "Request timed out")])
    assert fx.run(T0).returncode == 0
    assert "해제 예상" not in fx.to(PLANNER)[0] and "기타 API 오류 1" in fx.to(PLANNER)[0] and "사용량 제한 0" in fx.to(PLANNER)[0]


def test_release_time_in_error_text_is_shown_verbatim(tmp_path):  # arch 보강 ⓘ — 문구에 시각이 있을 때만 그 값
    fx = Fx(tmp_path)
    fx.add("t-a#1", [_user("a0", T0 - 900), _normal("a1", T0 - 880)])
    fx.run(T0 - 600)
    fx.add("t-a#1", [_user("a2", T0 - 70), *_error("a-err", T0 - 60, "5-hour limit reached resets 3am")])
    assert fx.run(T0).returncode == 0
    assert "해제 예상: 3am" in fx.to(PLANNER)[0] and "미상" not in fx.to(PLANNER)[0]

def test_release_time_is_first_normal_record_after_last_error(tmp_path):  # DA⑥ C1 ① — 뒤 응답·재시작으로 안 바뀐다
    fx = _outage_fx(tmp_path)
    fx.run(T0)
    fx.add("t-c#1", [_user("c2", T0 + 290), _normal("c3", T0 + 300), _user("c4", T0 + 400), _normal("c5", T0 + 420)])
    assert fx.run(T0 + 450).returncode == 0
    end = [b for b in fx.to(PLANNER) if b.startswith("[API 장애 끝 ")]
    assert len(end) == 1 and end[0].startswith("[API 장애 끝 00:05 · 약 6분]"), end
    fx.add("t-c#1", [_normal("c6", T0 + 500)])
    assert fx.run(T0 + 560).returncode == 0 and len([b for b in fx.to(PLANNER) if "끝" in b]) == 1


def test_retry_after_phrase_is_shown_with_its_basis(tmp_path):  # DA⑥ C1 ② — resets 와 retry after 둘 다
    fx = Fx(tmp_path)
    fx.add("t-a#1", [_user("a0", T0 - 900), _normal("a1", T0 - 880)])
    fx.run(T0 - 600)
    fx.add("t-a#1", [_user("a2", T0 - 70), *_error("a-err", T0 - 60, "API Error: 429 rate_limit_error retry after 120 seconds")])
    assert fx.run(T0).returncode == 0
    assert "해제 예상: 00:01 (문구: retry after 120s)" in fx.to(PLANNER)[0] and "미상" not in fx.to(PLANNER)[0]


def test_two_teams_same_planner_get_one_start_and_one_end(tmp_path):  # DA⑥ C2 — 수신자별 전역 1통 · 재개는 좌석표별
    ta, tb = Fx(tmp_path, name="team-a"), Fx(tmp_path, name="team-b")
    for fx, seat in ((ta, "t-a#9"), (tb, "t-b#9")):
        fx.add(seat, [_user("u0", T0 - 900), _normal("n0", T0 - 880)])
        assert fx.run(T0 - 600).returncode == 0
        fx.add(seat, [_user("u1", T0 - 70), *_error(f"{seat}-err", T0 - 60, "API Error: 429 rate_limit_error")])
    for fx in (ta, tb):
        assert fx.run(T0).returncode == 0
    assert len([b for b in ta.to(PLANNER) if b.startswith("[API 장애 시작")]) == 1
    for fx, seat in ((ta, "t-a#9"), (tb, "t-b#9")):
        fx.add(seat, [_user("u2", T0 + 290), _normal("n1", T0 + 300)])
    for fx in (ta, tb):
        assert fx.run(T0 + 330).returncode == 0
    assert len([b for b in ta.to(PLANNER) if b.startswith("[API 장애 끝")]) == 1
    assert len(ta.to("t-a#9")) == 0 and len(ta.to("t-b#9")) == 0  # 정상으로 돌아온 좌석은 재개 대상 아님


def test_two_teams_each_resume_own_cut_seats_once(tmp_path):  # DA⑥ C2 — 재개 uuid 는 좌석표별 그대로
    ta, tb = Fx(tmp_path, name="team-a"), Fx(tmp_path, name="team-b")
    for fx, seat in ((ta, "t-a#9"), (tb, "t-b#9")):
        fx.add(seat, [_user("u0", T0 - 900), _normal("n0", T0 - 880)])
        fx.add("t-ok#" + seat[2], [_user("k0", T0 - 900), _normal("k1", T0 - 880)])
        assert fx.run(T0 - 600).returncode == 0
        fx.add(seat, [_user("u1", T0 - 70), *_error(f"{seat}-err", T0 - 60, "API Error: 429 rate_limit_error")])
    for fx in (ta, tb):
        fx.run(T0)
    for fx in (ta, tb):
        fx.add("t-ok#" + ("a" if fx is ta else "b"), [_user("k2", T0 + 290), _normal("k3", T0 + 300)])
        assert fx.run(T0 + 330).returncode == 0
        assert fx.run(T0 + 400).returncode == 0
    calls = ta.calls()
    assert len([c for c in calls if c[0] == "t-a#9"]) == 1 and len([c for c in calls if c[0] == "t-b#9"]) == 1
    assert len([c for c in calls if c[0] == PLANNER]) == 2  # 시작 1 + 끝 1


def test_ongoing_outage_adds_no_notice(tmp_path):  # 1ⓑ · 1ⓔ(장애 중 재개 0)
    fx = _outage_fx(tmp_path)
    fx.run(T0)
    fx.add("t-c#1", [_user("c2", T0 + 30), *_error("c-err", T0 + 40, "API Error: 503 upstream")])
    assert fx.run(T0 + 60).returncode == 0 and fx.run(T0 + 120).returncode == 0
    assert len(fx.calls()) == 1


def test_recovery_notice_and_one_resume_per_cut_seat(tmp_path):  # 1ⓒ · 1ⓓ
    fx = _outage_fx(tmp_path)
    fx.run(T0)
    fx.add("t-c#1", [_user("c2", T0 + 290), _normal("c3", T0 + 300)])
    assert fx.run(T0 + 330).returncode == 0
    end = [b for b in fx.to(PLANNER) if b.startswith("[API 장애 끝 ")]
    assert len(end) == 1 and "약 6분" in end[0] and "00:05" in end[0] and "재개 보낼 좌석 2" in end[0]
    for seat in ("t-a#1", "t-b#1"):
        bodies = fx.to(seat)
        assert len(bodies) == 1 and bodies[0].startswith("[재개] API 오류로 끊긴 턴(") and "마지막 지시 이어서" in bodies[0]
    assert fx.to("t-c#1") == []  # 정상 IDLE 좌석 0
    assert {f for _d, f, _b in fx.calls()} == {"ft-api-outage"}
    assert {"a-err", "b-err"} <= set(json.loads(fx.state.read_text(encoding="utf-8"))["resumed"])


def test_same_uuid_never_resent_even_after_restart(tmp_path):  # 1ⓔ
    fx = _outage_fx(tmp_path)
    fx.run(T0)
    fx.add("t-c#1", [_user("c2", T0 + 290), _normal("c3", T0 + 300)])
    fx.run(T0 + 330)
    n = len(fx.calls())
    for t in (T0 + 400, T0 + 460, T0 + 520):  # 프로세스 재시작 = 매번 새 프로세스 · 좌석은 아직 응답 전
        assert fx.run(t).returncode == 0
    assert len(fx.calls()) == n


def test_idle_and_human_interrupted_seats_are_not_targets(tmp_path):  # 1ⓒ
    fx = Fx(tmp_path)
    fx.add("t-a#1", [_user("a0", T0 - 900), _normal("a1", T0 - 880)])
    fx.run(T0 - 600)
    fx.add("t-b#1", [_user("b0", T0 - 60), _user("b1", T0 - 50, "[Request interrupted by user]"),
                     {"type": "system", "subtype": "turn_duration", "timestamp": _iso(T0 - 50), "durationMs": 9}])
    assert fx.run(T0).returncode == 0
    assert fx.calls() == []


def test_missing_or_corrupt_state_records_baseline_only(tmp_path):  # 1ⓕ
    fx = Fx(tmp_path)
    fx.add("t-a#1", [_user("a2", T0 - 70), *_error("a-err", T0 - 60, "API Error: 503 x")])
    assert fx.run(T0).returncode == 0 and fx.calls() == [] and fx.state.exists()
    fx.state.write_text("{not json", encoding="utf-8")
    r = fx.run(T0 + 60)
    assert r.returncode == 0 and fx.calls() == [] and json.loads(fx.state.read_text(encoding="utf-8"))
    assert "state" in r.stderr  # 조용한 생략 0


def test_mbox_failure_is_loud_and_retried_next_tick(tmp_path):  # 1ⓔ · 7초 룰 밖 조용한 실패 0
    fx = _outage_fx(tmp_path)
    fx.mbox.write_text('#!/bin/bash\necho fail >&2\nexit 3\n', encoding="utf-8")
    r = fx.run(T0)
    assert r.returncode != 0 and "ERROR" in r.stderr
    fx.mbox.write_text(f'#!/bin/bash\necho "$2|$3|$4" >> "{fx.log}"\n', encoding="utf-8")
    assert fx.run(T0 + 60).returncode == 0
    assert len(fx.to(PLANNER)) == 1 and fx.to(PLANNER)[0].startswith("[API 장애 시작 ")


def _scenario_calls(script: Path, tmp: Path) -> tuple[int, list[tuple[str, ...]]]:
    """→ (장애 중 틱 뒤까지 나간 쪽지 수, 전체 쪽지)."""
    tmp.mkdir(parents=True, exist_ok=True)
    fx = _outage_fx(tmp, script)
    fx.run(T0)
    fx.run(T0 + 60)  # 장애 중 틱 — 재개 0 이어야 한다
    during = len(fx.calls())
    fx.add("t-c#1", [_user("c2", T0 + 290), _normal("c3", T0 + 300)])
    fx.run(T0 + 330)
    fx.run(T0 + 400)  # 재시작 — 같은 uuid 재발신 0 이어야 한다
    return during, fx.calls()


def _mutant(tmp: Path, marker: str, replace: tuple[str, str] | None = None, target: Path = MODULE) -> Path:
    """marker 줄을 지운(또는 replace 로 조건만 무력화한) 복사본 — 형제 모듈도 같은 폴더에 둔다."""
    lines = target.read_text(encoding="utf-8").splitlines(keepends=True)
    hit = [ln for ln in lines if marker in ln]
    assert len(hit) == 1, f"marker {marker} x{len(hit)}"
    kept = [ln.replace(*replace) if replace and marker in ln else ln for ln in lines if replace or marker not in ln]
    d = tmp / "mutant"
    d.mkdir()
    for src in (MODULE, UTIL):
        _ = (d / src.name).write_text("".join(kept) if src == target else src.read_text(encoding="utf-8"), encoding="utf-8")
    return d / MODULE.name


def _good(result: tuple[int, list[tuple[str, ...]]]) -> bool:
    during, calls = result
    resumes = [c for c in calls if c[2].startswith("[재개]")]
    starts = [c for c in calls if c[2].startswith("[API 장애 시작")]
    return during == 1 and len(resumes) == 2 and len(starts) == 1


def test_baseline_scenario_is_good(tmp_path):
    assert _good(_scenario_calls(MODULE, tmp_path))


def test_mutant_without_no_resume_during_outage_fails(tmp_path):  # 변이 ⓐ
    assert not _good(_scenario_calls(_mutant(tmp_path, "GUARD:no-resume-during-outage", ("!= \"RECOVERED\"", "== \"NEVER\"")), tmp_path / "w"))


def test_mutant_without_uuid_record_fails(tmp_path):  # 변이 ⓑ
    assert not _good(_scenario_calls(_mutant(tmp_path, "GUARD:uuid-record"), tmp_path / "w"))


def _two_teams(tmp: Path, barrier: bool) -> tuple[Fx, Fx]:
    ta, tb = Fx(tmp, name="team-a", barrier=barrier), Fx(tmp, name="team-b", barrier=barrier)
    for fx, seat in ((ta, "t-a#9"), (tb, "t-b#9")):
        fx.add(seat, [_user("u0", T0 - 900), _normal("n0", T0 - 880)])
        assert fx.run(T0 - 600).returncode == 0
        fx.add(seat, [_user("u1", T0 - 70), *_error(f"{seat}-err", T0 - 60, "API Error: 429 rate_limit_error")])
    return ta, tb


def _parallel(ta: Fx, tb: Fx, now: int) -> list[subprocess.CompletedProcess[str]]:
    with ThreadPoolExecutor(2) as pool:
        return list(pool.map(lambda fx: fx.run(now), (ta, tb)))


def _two_team_concurrent(tmp: Path, script: Path = MODULE) -> tuple[list[str], list[str]]:
    """같은 planner 를 가리키는 두 좌석표의 제품 프로세스 2개를 «동시에» → (시작 알림들, 끝 알림들)."""
    ta, tb = _two_teams(tmp, barrier=True)
    ta.script = tb.script = script
    assert all(r.returncode == 0 for r in _parallel(ta, tb, T0))
    shutil.rmtree(tmp / "barrier", ignore_errors=True)
    for fx, seat in ((ta, "t-a#9"), (tb, "t-b#9")):
        fx.add(seat, [_user("u2", T0 + 290), _normal("n1", T0 + 300)])
    assert all(r.returncode == 0 for r in _parallel(ta, tb, T0 + 330))
    notes = ta.to(PLANNER)
    return [b for b in notes if b.startswith("[API 장애 시작")], [b for b in notes if b.startswith("[API 장애 끝")]


def test_concurrent_two_processes_send_one_start_and_one_end(tmp_path):  # 교정 2 계약 4 · DA⑥ HOLD2 C2
    starts, ends = _two_team_concurrent(tmp_path)
    assert len(starts) == 1 and len(ends) == 1, (starts, ends)


def test_mutant_without_notify_lock_sends_twice(tmp_path):  # 변이 — 잠금 제거 → 2통
    starts, ends = _two_team_concurrent(tmp_path, _mutant(tmp_path, "GUARD:flock", ("fcntl.flock(fh,", "(lambda *_: None)(fh,"), UTIL))
    assert len(starts) + len(ends) > 2


def test_lock_wait_over_limit_is_one_error_line_and_no_send(tmp_path):  # 교정 2 계약 2 — 건너뛰기 아님 · 다음 틱이 재시도
    ta, _tb = _two_teams(tmp_path, barrier=False)
    lock = tmp_path / "state" / f"notify-{PLANNER.replace('#', '_')}.json.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        r = ta.run(T0, ["--lock-timeout", "0.3"])
    assert r.returncode == 0 and ta.calls() == []
    errs = [ln for ln in r.stderr.splitlines() if "ERROR" in ln]
    assert len(errs) == 1 and PLANNER in errs[0] and "시작" in errs[0] and "0.3" in errs[0], r.stderr
    assert ta.run(T0 + 60).returncode == 0 and len(ta.to(PLANNER)) == 1  # 다음 틱 재시도 성공


def test_kit_copy_is_identical():  # 키트 미러 drift 0
    assert KIT_MODULE.read_bytes() == MODULE.read_bytes()
    assert (KIT_DIR / "ft_api_outage_util.py").read_bytes() == UTIL.read_bytes()


def test_module_under_200_lines():
    assert len(MODULE.read_text(encoding="utf-8").splitlines()) <= 200


def test_tick_dry_run_lists_api_outage_kind(tmp_path):  # 2 — ft-tick 호출부
    seats = tmp_path / "seats.json"
    seats.write_text(json.dumps({"_master": "t-m#1", "t-m#1": {"role": "master", "tick": None}}), encoding="utf-8")
    env = {**os.environ, "FT_TICK_SEATS": str(seats), "FT_TICK_WT_SWEEP": "0", "FT_TICK_HIL": "0","FT_TICK_DRIFT": "0",
           "FT_TICK_NEWS_LEDGER": "0", "FT_TICK_IDLE_ENABLED": "0", "FT_TICK_STATE_DIR": str(tmp_path / "st"),
           "FT_TICK_MBOX": str(tmp_path / "mbox.sh")}  # r459 뒤 comm 폴더 없는 임시 루트는 mbox 를 직접 준다(r497 에서 RED 수리)
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        env.pop(k, None)
    r = subprocess.run(["bash", str(SCRIPTS / "ft-tick.sh"), "--once", "--dry-run"], capture_output=True, text=True, env=env, timeout=60)
    assert "DRY kind=api-outage" in r.stdout, r.stdout + r.stderr


def test_tick_survives_outage_tool_failure_with_one_error_line(tmp_path):  # 2 — 실패해도 틱은 계속
    seats = tmp_path / "seats.json"
    seats.write_text(json.dumps({"_master": "t-m#1", "_hil_route": PLANNER, "t-m#1": {"role": "master", "tick": None}}), encoding="utf-8")
    bad = tmp_path / "bad.py"
    bad.write_text("import sys\nprint('boom', file=sys.stderr)\nsys.exit(4)\n", encoding="utf-8")
    env = {**os.environ, "FT_TICK_SEATS": str(seats), "FT_TICK_WT_SWEEP": "0", "FT_TICK_HIL": "0","FT_TICK_DRIFT": "0", "FT_TICK_NEWS_LEDGER": "0",
           "FT_TICK_IDLE_ENABLED": "0", "FT_TICK_STATE_DIR": str(tmp_path / "st"), "FT_TICK_PIDFILE": str(tmp_path / "pid"),
           "FT_TICK_STALL_INTERVAL": "99999", "FT_TICK_API_OUTAGE_BIN": str(bad), "FT_TICK_STAMP_PREFIX": str(tmp_path / "stamp-"),
           "FT_TICK_API_OUTAGE_STATE": str(tmp_path / "ao.json"), "FT_TICK_MBOX": str(tmp_path / "mbox.sh"), "FT_MODEL_SWAP": "0"}
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        env.pop(k, None)
    r = subprocess.run(["bash", str(SCRIPTS / "ft-tick.sh"), "--once"], capture_output=True, text=True, env=env, timeout=60)
    assert r.returncode == 0, r.stderr
    errs = [ln for ln in r.stderr.splitlines() if "api_outage" in ln and "ERROR" in ln]
    assert len(errs) == 1, r.stderr
    assert "no active seat" in r.stdout  # 틱의 나머지(pass 끝)까지 계속 돌았다

