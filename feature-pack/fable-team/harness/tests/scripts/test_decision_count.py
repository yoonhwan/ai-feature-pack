"""R214(판정 1804) ft-decision-count.sh — 결정 인터뷰·스크립트·팀 대기 건수 한 줄 + --alarm. 임시 FT_ROOT·가짜 mbox·임시 HIL_DIR 만 쓴다(실 인박스·실 mbox·실 /tmp/h* 0)."""
import json
import os
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
NOW = datetime(2026, 10, 15, 18, 0, 0)
TWO_S = {"FT_DECISION_BUDGET_S": "2"}  # 예산 «기전» 을 보는 시험만 짧은 예산을 명시한다(기본값은 부하 여유 — R303)
ME = "byz-planner-master-claude#50"
QNAME = "byz-planner-master-claude.jsonl"


def run(env, *args, extra=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    e.update(extra or {})
    e.update(FT_ROOT=str(env["root"]), FT_DECISION_NOW=NOW.isoformat(), HIL_DIR=str(env["hil"]), HIL_CLIP="0",
             FT_SECRET_JUDGE=str(env["root"] / "none.py"), FT_DECISION_MBOX=str(env["mbox"]), FT_DECISION_TMUX=str(env["root"] / "tmux-stub.sh"),
             FT_DECISION_AUTONOMY_QUEUE=str(env["root"] / "AQ.md"), FT_DECISION_MERGE_QUEUE=str(env["root"] / "MQ.md"),
             FT_DECISION_FLAG_DECISIONS=str(env["root"] / "FD.md"),  # r517: 루트 자리는 ref 본문 — git 밖 임시 루트라 표 자리를 env 로 고정
             FT_FLAG_OFF_REPO=str(env["root"] / "flagrepo"), FT_FLAG_OFF_REF="HEAD")  # R239: 꺼진 플래그 검사는 플래그 0 인 임시 git 저장소만 본다
    return subprocess.run(["bash", str(BIN / "ft-decision-count.sh"), *args], capture_output=True, text=True, env=e, timeout=30)


def row(seq, cls, frm="byz-cfo-master-claude#1", ago=5, closed=False):
    return {"seq": seq, "ts": (NOW - timedelta(minutes=ago)).isoformat(), "from": frm, "cls": cls, "prio": 2.0, "group": f"g{seq}",
            "body_path": "", "mark": {"kind": "처리"} if closed else None, "reported": closed}


def put(env, rows):
    (env["root"] / ".fable-team/state/inbox").mkdir(parents=True, exist_ok=True)
    (env["root"] / ".fable-team/state/inbox" / QNAME).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


@pytest.fixture
def env(tmp_path):
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / "design").mkdir()  # R382b: planner 폴더는 TEAMS.md 폴더 칸으로 풀린다
    (tmp_path / "design/TEAMS.md").write_text("| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n", encoding="utf-8")
    (tmp_path / ".fable-team/seats-planner.json").write_text(json.dumps({"_master": ME, "_cards_wt": "none"}))
    mbox = tmp_path / "mbox-stub.sh"
    mbox.write_text(f'#!/usr/bin/env bash\n[ -z "$STUB_FAIL" ] || exit 3\necho "$@" >> "{tmp_path}/mbox.log"\n')
    (tmp_path / "live.txt").write_text("byz-cfo-master-claude#1\nbyz-graphics-master-claude#3\nbyz-loom-master-claude#1\n")  # tmux 세션 실재 대역
    tmux = tmp_path / "tmux-stub.sh"
    tmux.write_text(f'#!/usr/bin/env bash\necho "$@" >> "{tmp_path}/tmux.log"\n[ -z "$STUB_TMUX_ERR" ] || {{ echo "$STUB_TMUX_ERR" >&2; exit 1; }}\n[ -z "$STUB_TMUX_FAIL" ] || {{ echo boom >&2; exit 2; }}\n'
                    f'[ -z "$STUB_TMUX_SLEEP" ] || sleep "$STUB_TMUX_SLEEP"\ncat "{tmp_path}/live.txt"\n')  # list-sessions 대역: 호출 기록 · 오류 · 느림
    tmux.chmod(0o755)
    (tmp_path / ".fable-team/seats-teams.json").write_text(json.dumps({"byz-roster-master-claude#1": {"role": "master"}}))  # 명부 현역이지만 세션 없음
    (tmp_path / "hil").mkdir()
    git = ["git", "-C", str(tmp_path / "flagrepo")]
    subprocess.run(["git", "init", "-q", str(tmp_path / "flagrepo")], check=True)
    subprocess.run([*git, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "e"], check=True)
    return {"root": tmp_path, "hil": tmp_path / "hil", "mbox": mbox}


def table(env, name, head, rows):
    (env["root"] / name).write_text("| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n" + "".join("| " + " | ".join(r) + " |\n" for r in rows))


def test_a_decisions_from_inbox_and_merge_queue(env):
    put(env, [row(1, "②"), row(2, "②"), row(3, "③")] + [row(10 + i, "⑤") for i in range(5)])
    r = run(env)
    assert r.returncode == 0 and r.stdout.startswith("결정 인터뷰 3건 · 스크립트 0건 · 팀 대기 3건"), r.stdout + r.stderr
    table(env, "MQ.md", ["접수", "상태"], [["a", "대기"], ["b", "✅ 판정 1 승인 · 집행 대기"]])
    assert run(env).stdout.startswith("결정 인터뷰 4건")


def test_b_closed_not_counted(env):
    put(env, [row(1, "②", closed=True), row(2, "②")])
    assert run(env).stdout.startswith("결정 인터뷰 1건")


def test_c_autonomy_queue_without_done_column_counts_all_rows_with_marker(env):
    put(env, [])
    table(env, "AQ.md", ["자율", "질문"], [["A2", "x"], ["A2", "y"]])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 2건") and "(자율 큐 처리 표식 없음)" in out
    table(env, "AQ.md", ["자율", "질문", "처리됨"], [["A2", "x", ""], ["A2", "y", "완료"]])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 1건") and "표식 없음" not in out


def test_d_scripts_count_only_unrun_unsuperseded(env):
    put(env, [])
    for n in "ABC":
        (env["root"] / f"{n}.sh.hil").write_text("exit 0\n")
    def add(n, *a):
        e = {**os.environ, "HIL_DIR": str(env["hil"]), "HIL_CLIP": "0", "FT_SECRET_JUDGE": str(env["root"] / "none.py")}
        subprocess.run(["bash", str(BIN / "ft-hil.sh"), "--add", str(env["root"] / f"{n}.sh.hil"), *a], capture_output=True, text=True, env=e, check=True)

    add("A")
    add("B")
    add("C", "--supersedes", "h2")
    subprocess.run(["bash", str(env["hil"] / "h1")], check=True, capture_output=True)
    assert " · 스크립트 1건 · " in run(env).stdout  # h1 실행 · h2 대체됨 · h3 만 남음


def test_e_team_wait_longest_and_excludes_planner(env):
    put(env, [row(1, "④", "byz-graphics-master-claude#3", ago=40), row(2, "②", "byz-cfo-master-claude#1", ago=10),
              row(3, "④", "byz-planner-master-claude#49", ago=100), row(4, "⑤", "byz-loom-master-claude#1", ago=200)])
    assert "팀 대기 2건(가장 오래 byz-graphics-master-claude#3 40분)" in run(env).stdout
    d = run(env, "--detail").stdout.splitlines()
    assert len(d) == 3 and d[1].startswith("  #1 ") and "40분" in d[1]


def test_f_unreadable_inbox_is_rc4_without_numbers(env):
    r = run(env)
    assert r.returncode == 4 and r.stdout == "" and "ERROR" in r.stderr
    assert run(env, "--bogus").returncode == 2


def test_g_alarm_once_per_seq_and_rearms_after_close(env):
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31), row(8, "④", "byz-cfo-master-claude#1", ago=10)])
    log = env["root"] / "mbox.log"
    assert run(env, "--alarm").returncode == 0 and log.read_text().count("[결정 대기 경보]") == 1
    assert "byz-graphics-master-claude#3 #7 31분" in log.read_text() and ME in log.read_text()
    run(env, "--alarm")
    assert log.read_text().count("[결정 대기 경보]") == 1
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31, closed=True)])
    run(env, "--alarm")
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31)])
    run(env, "--alarm")
    assert log.read_text().count("[결정 대기 경보]") == 2


def test_g2_alarm_send_failure_is_rc4_and_retried(env):
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31)])
    assert run(env, "--alarm", extra={"STUB_FAIL": "1"}).returncode == 4
    assert run(env, "--alarm").returncode == 0 and (env["root"] / "mbox.log").read_text().count("#7") == 1


def test_h_463_rows_under_two_seconds(env):
    put(env, [row(i, ["①", "②", "③", "④", "⑤", "⑥"][i % 6], f"byz-t{i % 9}-master-claude#1", ago=i) for i in range(463)])
    t0 = time.time()
    r = run(env)
    assert r.returncode == 0 and time.time() - t0 <= 2, r.stdout + r.stderr


def test_j_retired_sender_is_memo_not_team_wait(env):
    put(env, [row(1, "④", "byz-old-master-claude#7", ago=900), row(2, "④", "byz-roster-master-claude#1", ago=900)])  # 세션 없음 · 명부 현역도 세션 없으면 메모
    out = run(env).stdout
    assert "팀 대기 0건" in out and "(옛 좌석 미닫힘 2)" in out
    put(env, [row(1, "④", "byz-old-master-claude#7", ago=900), row(3, "④", "byz-loom-master-claude#1", ago=50)])
    out = run(env).stdout
    assert "팀 대기 1건(가장 오래 byz-loom-master-claude#1 50분)" in out and "(옛 좌석 미닫힘 1)" in out


def test_k_alarm_is_one_mail_per_run_even_for_many_seqs(env):
    put(env, [row(100 + i, "④", "byz-graphics-master-claude#3", ago=40 + i) for i in range(12)])
    log = env["root"] / "mbox.log"
    assert run(env, "--alarm").returncode == 0
    body = log.read_text()
    assert body.count("[결정 대기 경보]") == 1 and "새로 30분 넘은 팀 대기 12건" in body and "외 9건" in body and len(body.splitlines()) <= 5
    run(env, "--alarm")
    assert log.read_text() == body  # 재실행 0통
    put(env, [row(100 + i, "④", "byz-graphics-master-claude#3", ago=40 + i) for i in range(12)] + [row(200, "④", "byz-cfo-master-claude#1", ago=35)])
    run(env, "--alarm")
    assert log.read_text().count("[결정 대기 경보]") == 2 and "팀 대기 1건" in log.read_text()


def test_i_news_head_gets_decision_line_right_under_it():
    import sys
    sys.path.insert(0, str(BIN))
    from ft_news_ledger_text import MAX_BYTES, render_parts
    lead = "결정 인터뷰 3건 · 스크립트 1건 · 팀 대기 0건"
    new = {("3", "", f"팀{i}"): ("x" * 60,) for i in range(60)}
    parts = render_parts(NOW, new, [("새로", "a")], "ledger.md", (), lead)
    assert len(parts) > 1 and all(p.split("\n")[1] == lead and len(p.encode()) <= MAX_BYTES for p in parts)
    assert lead not in render_parts(NOW, new, [("새로", "a")], "ledger.md")[0]


def test_l_sensor_error_is_rc4_not_empty_and_alarm_state_untouched(env):
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31)])
    log, state = env["root"] / "mbox.log", env["root"] / ".fable-team/state/decision-alarm.json"
    assert run(env, "--alarm").returncode == 0 and log.read_text().count("[결정 대기 경보]") == 1
    before = state.read_text()
    r = run(env, extra={"STUB_TMUX_FAIL": "1"})
    assert r.returncode == 4 and r.stdout == "" and "tmux list-sessions rc=2" in r.stderr
    assert run(env, "--alarm", extra={"STUB_TMUX_FAIL": "1"}).returncode == 4 and state.read_text() == before
    assert run(env, "--alarm").returncode == 0 and log.read_text().count("[결정 대기 경보]") == 1  # 정상→오류→정상: 같은 열린 seq 경보 누적 1통
    (env["root"] / "live.txt").write_text("")
    assert "팀 대기 0건 (옛 좌석 미닫힘 1)" in run(env).stdout  # 센서 정상 + 세션 없음 = 메모


def test_m_broken_source_table_is_rc4_but_empty_table_is_zero(env):
    put(env, [])
    table(env, "MQ.md", ["접수", "한 줄"], [["a", "x"]])
    r = run(env)
    assert r.returncode == 4 and "상태" in r.stderr and r.stdout == ""
    table(env, "MQ.md", ["접수", "상태"], [["a"]])
    assert run(env).returncode == 4  # 상태 칸보다 짧은 행
    (env["root"] / "MQ.md").write_text("표 없는 글\n")
    assert run(env).returncode == 4
    table(env, "MQ.md", ["접수", "상태"], [])
    assert run(env).stdout.startswith("결정 인터뷰 0건")  # 빈 표 = 0
    table(env, "AQ.md", ["자율", "질문", "처리됨"], [["A2", "x"]])
    assert run(env).returncode == 4  # 처리됨 칸보다 짧은 행


def test_n_one_tmux_call_for_many_seats_within_two_seconds(env):
    put(env, [row(i, "④", f"byz-t{i}-master-claude#1", ago=40) for i in range(5)])
    t0 = time.time()
    r = run(env, extra={"STUB_TMUX_SLEEP": "1.1", **TWO_S})
    assert r.returncode == 0 and time.time() - t0 <= 2.0, r.stderr
    assert len((env["root"] / "tmux.log").read_text().splitlines()) == 1  # 좌석 5 + 느린 센서 → 호출 1회
    r = run(env, extra={"STUB_TMUX_SLEEP": "3", **TWO_S})
    assert r.returncode == 4 and "예산" in r.stderr  # 전체 2 s 예산 초과 = rc4


def test_o_only_missing_socket_means_no_server_other_connect_errors_are_rc4(env):
    put(env, [row(7, "④", "byz-graphics-master-claude#3", ago=31)])
    log, state = env["root"] / "mbox.log", env["root"] / ".fable-team/state/decision-alarm.json"
    assert run(env, "--alarm").returncode == 0 and log.read_text().count("[결정 대기 경보]") == 1
    before = state.read_text()
    denied = {"STUB_TMUX_ERR": "error connecting to /tmp/tmux-501/default (Permission denied)"}
    r = run(env, extra=denied)
    assert r.returncode == 4 and r.stdout == "" and "Permission denied" in r.stderr
    assert run(env, "--alarm", extra=denied).returncode == 4 and state.read_text() == before
    assert run(env, "--alarm").returncode == 0 and log.read_text().count("[결정 대기 경보]") == 1  # 오류 왕복 뒤 같은 seq 경보 누적 1통
    for ok in ("no server running on /tmp/tmux-501/default", "error connecting to /tmp/tmux-501/default (No such file or directory)"):
        assert "팀 대기 0건 (옛 좌석 미닫힘 1)" in run(env, extra={"STUB_TMUX_ERR": ok}).stdout  # 서버 없음만 세션 0


def test_p_slow_hil_lookup_is_bounded_by_remaining_total_budget(env):
    put(env, [])
    slow = env["root"] / "hil-slow.sh"
    slow.write_text("exec sleep 5\n")
    t0 = time.time()
    r = run(env, extra={"FT_DECISION_HIL": str(slow), **TWO_S})
    assert r.returncode == 4 and "ft-hil.sh" in r.stderr and time.time() - t0 <= 3.0, r.stderr  # 상한 = min(7 s, 남은 2 s 예산)


def test_q_default_budget_survives_a_loaded_machine_but_stays_under_callers_7s(env):
    """R303(판정 1395): 실사용 hook 이 부하 때 rc4 62건(ft-hil.sh 시간 초과) — 기본 예산은 2.5 s 느린 센서를 견디고, 호출자(ft_news_ledger timeout=7) 밑이어야 한다."""
    put(env, [row(1, "④", "byz-cfo-master-claude#1", ago=40)])
    assert run(env, extra={"STUB_TMUX_SLEEP": "2.5"}).returncode == 0
    r = run(env, extra={"STUB_TMUX_SLEEP": "7.5"})
    assert r.returncode == 4 and "예산" in r.stderr  # 기본 예산은 7 s 밖으로 새지 않는다
    slow = env["root"] / "hil-slow3.sh"
    slow.write_text('[ "$1" = "--pending" ] && sleep 3\n')  # 실사용 rc4 62건의 원인 호출: ft-hil.sh --pending 이 3 s 걸려도 기본 예산(5 s)에서는 통과
    put(env, [])
    assert run(env, extra={"FT_DECISION_HIL": str(slow)}).returncode == 0
    assert run(env, extra={"FT_DECISION_HIL": str(slow), **TWO_S}).returncode == 4  # 짧은 예산이면 같은 호출이 시간 초과(상한 = min(7, 남은 예산))


def test_r_slow_git_flag_lookups_share_one_total_deadline(env):
    """R303 DA⑥ H1: 플래그 조회 git 3회가 각각 «남은 예산 한 번 계산한 값» 을 쓰면 5 s 예산이 7.5 s 로 샌다 — 마감 시각으로 조회마다 남은 시간만 허용한다."""
    put(env, [row(1, "④", "byz-cfo-master-claude#1", ago=40)])
    fake = env["root"] / "fakebin"
    fake.mkdir()
    git = fake / "git"
    git.write_text('#!/bin/sh\nsleep 2.5\ncase "$3" in\ngrep) echo "HEAD:clients/web/src/a.ts:1:process.env.NEXT_PUBLIC_X === \'1\'";;\nshow) echo "ARG NEXT_PUBLIC_X"; echo "NEXT_PUBLIC_X=1";;\nesac\n')
    git.chmod(0o755)
    t0 = time.time()
    r = run(env, extra={"PATH": f"{fake}{os.pathsep}{os.environ['PATH']}"})
    assert r.returncode == 4 and "git" in r.stderr and time.time() - t0 <= 5.5, (time.time() - t0, r.stdout, r.stderr)  # 총 ≤ 예산 5 s + 0.5 s


@pytest.mark.parametrize("bad", ["0", "-1", "abc", "600", "6.5", "nan"])
def test_s_budget_env_outside_zero_to_six_is_rc2_not_silent(env, bad):
    """R303 DA⑥ H2: 7초 룰 밖 값(600)·0·음수·숫자 아님은 조용히 받지 않는다 — ERROR rc2."""
    put(env, [])
    r = run(env, extra={"FT_DECISION_BUDGET_S": bad})
    assert r.returncode == 2 and r.stdout == "" and "FT_DECISION_BUDGET_S" in r.stderr and "0 초과 6 이하 숫자" in r.stderr and "Traceback" not in r.stderr, r.stderr


def test_s2_empty_budget_env_is_default_and_six_is_allowed(env):
    put(env, [])
    assert run(env, extra={"FT_DECISION_BUDGET_S": ""}).returncode == 0
    assert run(env, extra={"FT_DECISION_BUDGET_S": "6"}).returncode == 0
