"""r849 — «Not logged in» 0초 실패만 반복하는 좌석: 판정 LOGGEDOUT · 틱 팀장 1통 · 깨우기·재개 0 · nano-close ③ 면제.

합성 jsonl(실 좌석 기록 복사 0) · 가짜 명부·tmux·mbox·seat-status 만 쓴다 — 실 좌석 깨우기·ring·쪽지 0.
R849_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_seat_logged_out_r849.sh 가 변이 사본을 넣어 ⓕ 를 본다).
재설계 r4 — 쪽지 키 = 로그아웃 구간 칸(state/stall/logged-out.<좌석>) 하나: ⓡ1 · ⓡ1b · ⓡ3.
"""
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from _stall_world import World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R849_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
NOW = int(time.time())


def iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def normal_turn(t: float, text: str = "ok") -> list[dict]:
    return [{"type": "user", "timestamp": iso(t - 5), "message": {"content": "go"}},
            {"type": "assistant", "timestamp": iso(t), "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": text}]}},
            {"type": "system", "subtype": "turn_duration", "timestamp": iso(t), "durationMs": 5000}]


def error_turn(t: float, error: str = "authentication_failed", text: str = "Not logged in · Please run /login", pad: int = 0,
               duration_ms: int = 142) -> list[dict]:
    """실측 꼴(arch 136 · tester#90 805행): 합성 오류 assistant + turn_duration 142ms."""
    return [{"type": "api-request", "timestamp": iso(t)},
            {"type": "user", "timestamp": iso(t), "message": {"content": "[발주 #1] recv" + "x" * pad}},
            {"type": "assistant", "timestamp": iso(t), "isApiErrorMessage": True, "error": error,
             "message": {"model": "<synthetic>", "content": [{"type": "text", "text": text}]}},
            {"type": "system", "subtype": "turn_duration", "timestamp": iso(t), "durationMs": duration_ms},
            {"type": "last-prompt", "lastPrompt": "x"}]


def write(path: Path, recs: list[dict]) -> Path:
    with path.open("a", encoding="utf-8") as fh:
        fh.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in recs)
    return path


def turn(path: Path, *flags: str) -> list[str]:
    r = subprocess.run(["bash", str(BIN / "ft-seat-status.sh"), "turn", "--file", str(path), *flags],
                       env={**os.environ, "FT_SEATS_JSON": "/nonexistent"}, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return r.stdout.split()


# ⓐ 인증 실패 0초 턴으로 끝남 → LOGGEDOUT <첫 실패> <연속 수> (앞 턴의 다른 API 오류는 연속에 안 든다)
def test_a_logged_out(tmp_path):
    f = write(tmp_path / "s.jsonl", normal_turn(NOW - 900) + error_turn(NOW - 600, "server_error", "API Error: 500")
              + error_turn(NOW - 300) + error_turn(NOW - 60))
    assert turn(f) == ["LOGGEDOUT", iso(NOW - 300), "2", "-", "jsonl"]
    js = json.loads(subprocess.run(["bash", str(BIN / "ft-seat-status.sh"), "turn", "--file", str(f), "--json"],
                                   env={**os.environ, "FT_SEATS_JSON": "/nonexistent"}, capture_output=True, text=True).stdout)
    assert js["state"] == "LOGGEDOUT" and js["failed_turns"] == 2 and js["duration_ms"] is None


def test_a_pending_queue_still_logged_out(tmp_path):  # 쪽지가 쌓여도(enqueue) 로그아웃은 로그아웃
    f = write(tmp_path / "s.jsonl", error_turn(NOW - 60) + [{"type": "queue-operation", "operation": "enqueue", "timestamp": iso(NOW - 30)}])
    assert turn(f)[:3] == ["LOGGEDOUT", iso(NOW - 60), "1"]


def test_a_long_streak_first_fail_is_stable(tmp_path):  # 연속 실패가 64KB 창을 넘어도 «첫 실패» 고정(쪽지 중복 키)
    recs = normal_turn(NOW - 9000)
    for i in range(60):
        recs += error_turn(NOW - 8000 + i * 10, pad=2000)
    f = write(tmp_path / "s.jsonl", recs)
    assert f.stat().st_size > 1 << 17
    assert turn(f)[:3] == ["LOGGEDOUT", iso(NOW - 8000), "60"]
    write(f, error_turn(NOW - 10, pad=2000))
    assert turn(f)[:3] == ["LOGGEDOUT", iso(NOW - 8000), "61"]


# ⓑ 로그인 복구(정상 턴) → IDLE · 다른 API 오류(429·overloaded) → LOGGEDOUT 아님 · 작업 중 → WORKING
def test_b_recovered_and_other_errors(tmp_path):
    f = write(tmp_path / "rec.jsonl", error_turn(NOW - 300) + normal_turn(NOW - 60))
    assert turn(f)[:2] == ["IDLE", iso(NOW - 60)]
    for err, text in (("rate_limit", "API Error: 429 rate_limit_error"), ("overloaded", "API Error: 529 Overloaded")):
        g = write(tmp_path / f"{err}.jsonl", normal_turn(NOW - 900) + error_turn(NOW - 60, err, text))
        assert turn(g)[0] == "IDLE", err
    h = write(tmp_path / "w.jsonl", error_turn(NOW - 60) + [{"type": "user", "timestamp": iso(NOW - 1), "message": {"content": "go"}}])
    assert turn(h)[0] == "WORKING"
    k = write(tmp_path / "n.jsonl", normal_turn(NOW - 60))
    assert turn(k)[0] == "IDLE"


# ⓒ 틱(ft-stall-scan): LOGGEDOUT 좌석 1 → 팀 _master 1통 · 같은 (좌석, 첫 실패) 두 번째 틱 0통 · 팀장 없음 = 로그 1줄
def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def test_c_tick_notifies_team_master_once(tmp_path):
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    w.mail("t1-nano#0", 7, 20)  # 미읽음 쪽지가 있어도 d(ring) 0
    assert scan(w).returncode == 0
    sends = [x for x in w.mbox_log() if x.startswith("send|")]
    assert len(sends) == 1 and sends[0].startswith("send|t1-master#1|") and "[로그아웃 좌석] t1-nano#0" in sends[0] and "재시작" in sends[0]
    assert not [x for x in w.mbox_log() if x.startswith("ring|")] and not w.tmux_log()
    w.advance(900)
    assert scan(w).returncode == 0 and len([x for x in w.mbox_log() if x.startswith("send|")]) == 1  # 같은 첫 실패 = 0통
    w.state("t1-nano#0", "LOGGEDOUT", 5)  # 같은 프로세스 · 첫 실패 시각만 바뀜 = 0통(키 = 프로세스 시작 · DA⑥ r1 ①)
    w.advance(900)
    assert scan(w).returncode == 0 and len([x for x in w.mbox_log() if x.startswith("send|")]) == 1
    w.state("t1-nano#0", "IDLE", 1)  # 로그인 복구(IDLE) → 서명 지움
    w.advance(900)
    assert scan(w).returncode == 0
    w.state("t1-nano#0", "LOGGEDOUT", 1)  # 다시 로그아웃 → 1통 더
    w.advance(900)
    assert scan(w).returncode == 0 and len([x for x in w.mbox_log() if x.startswith("send|")]) == 2


def test_c_master_itself_logged_out_logs_line(tmp_path):
    w = World(tmp_path)
    w.state("t1-master#1", "LOGGEDOUT", 30)
    w.state("t1-nano#0", "WORKING", 0)
    assert scan(w).returncode == 0
    assert not [x for x in w.mbox_log() if x.startswith("send|t1-master#1|")]
    assert any("act=l seat=t1-master#1" in x and "알릴 팀장 없음" in x for x in w.scan_log())


def test_c_broken_roster_logs_line(tmp_path):
    w = World(tmp_path)
    (w.root / ".fable-team/seats-broken.json").write_text("{not json", encoding="utf-8")
    assert scan(w).returncode == 0
    assert any("act=l ERROR 명부 못 읽음 seats-broken.json" in x for x in w.scan_log())


# ⓓ ft-idle-wake: LOGGEDOUT ring 0 + 로그 1줄(좌석·첫 실패 당 1회) · [완료·휴식] 닫기 대기 ring 0 · 보통 IDLE 은 ring 1
STATUS = ('#!/bin/sh\ncase "$1" in\n  turn) cat "$WSTUB/$2.turn" || exit 3;;\n'
          '  jsonl) [ -f "$WSTUB/$2.jsonl" ] && echo "$WSTUB/$2.jsonl" || exit 1;;\nesac\n')
TMUX = '#!/bin/sh\ncase "$1" in has-session) exit 0;; list-clients) exit 0;; esac\n'
MBOX = '#!/bin/sh\necho "$*" >> "$WSTUB/ring.log"\n'


def wake(tmp: Path) -> tuple[list[str], list[str]]:
    for n, body in (("status.sh", STATUS), ("tmux.sh", TMUX), ("mbox.sh", MBOX)):
        (tmp / n).write_text(body)
    env = {**os.environ, "FT_ROOT": str(tmp / "root"), "WSTUB": str(tmp), "FT_SEAT_STATUS": str(tmp / "status.sh"),
           "FT_TMUX": f"sh {tmp / 'tmux.sh'}", "FT_MBOX": str(tmp / "mbox.sh"), "FT_IDLE_SLOT_LOG": str(tmp / "slot.log")}
    r = subprocess.run(["bash", str(BIN / "ft-idle-wake.sh")], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    rl, lg = tmp / "ring.log", tmp / "root/.fable-team/state/idle-wake.log"
    return (rl.read_text().splitlines() if rl.exists() else []), (lg.read_text().splitlines() if lg.exists() else [])


def queue(tmp: Path, rows: list[tuple[int, str]]) -> None:
    (tmp / "root/.fable-team/comm").mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(NOW - 600))
    (tmp / "root/.fable-team/comm/mailbox.jsonl").write_text("".join(json.dumps({"seq": s, "ts": ts, "to": to, "from": "x", "body": "b"}) + "\n" for s, to in rows))


def card(tmp: Path, seat: str, name: str, last: str) -> None:
    """가짜 명부 행(index) + 카드 «## 상태» 절 — 마지막 줄 = last."""
    root = tmp / "root"
    (root / ".worktrees/wt-x/design/x/indices/완성").mkdir(parents=True, exist_ok=True)
    (root / f".worktrees/wt-x/design/x/indices/완성/{name}.md").write_text(f"# {name}\n## 상태\n- 2026-10-24 — 대기→진행\n{last}\n\n## 정본\n- 없음\n")
    f = root / ".fable-team/seats-x.json"
    rows = json.loads(f.read_text()) if f.exists() else {"_master": "x-master#1", "_cards_wt": "wt-x", "_cards": "design/x/indices"}
    rows[seat] = {"role": "nano", "index": f"design/x/indices/진행/{name}.md"}  # 명부는 진행 · 카드는 완성으로 옮겨 감
    f.write_text(json.dumps(rows, ensure_ascii=False))


def test_d_idle_wake_skips_logged_out_and_rested(tmp_path):
    (tmp_path / "root/.fable-team").mkdir(parents=True)
    (tmp_path / "lo#1.turn").write_text(f"LOGGEDOUT {iso(NOW - 900)} 3 - jsonl\n")
    for s in ("rest#1", "susp#1", "idle#1", "word#1", "open#1"):
        (tmp_path / f"{s}.turn").write_text(f"IDLE {iso(NOW - 900)} 1000 - jsonl\n")
    card(tmp_path, "rest#1", "c-rest", "세트: " + "a" * 40 + " · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0")
    card(tmp_path, "susp#1", "c-susp", "중단: 팀 정지 · 세트 " + "b" * 40 + " · 2026-10-24 14:56 · 재개 = planner 발주 뒤 새 세션")
    card(tmp_path, "open#1", "c-open", "- DA⑥ r1 HOLD → 반송 r2")  # 증거 줄 뒤에 다른 줄 = 닫기 대기 아님
    # DA⑥ r1 ② — 사용자 입력에 «[완료·휴식]» 글자가 든 정상 턴 · 카드 없음 → 보통 IDLE(ring 1)
    write(tmp_path / "word#1.jsonl", [{"type": "user", "timestamp": iso(NOW - 905), "message": {"content": "작업 중에는 [완료·휴식] 을 쓰지 마세요."}}]
          + normal_turn(NOW - 900, "알겠습니다")[1:])
    write(tmp_path / "idle#1.jsonl", normal_turn(NOW - 900, "[완료·휴식] 이라고 답만 함"))
    queue(tmp_path, [(11, "lo#1"), (12, "rest#1"), (13, "idle#1"), (15, "susp#1"), (16, "word#1"), (17, "open#1")])
    rings, log = wake(tmp_path)
    assert sorted(rings) == ["ring idle#1 13", "ring open#1 17", "ring word#1 16"]
    assert len([x for x in log if "lo#1" in x and "로그아웃 좌석" in x]) == 1
    assert len([x for x in log if "rest#1" in x and "닫기 대기" in x]) == 1 and len([x for x in log if "susp#1" in x and "닫기 대기" in x]) == 1
    queue(tmp_path, [(14, "lo#1")])  # 새 쪽지(seq 14)·첫 실패 시각 바뀜이어도 같은 로그아웃 = 로그 0 더
    (tmp_path / "lo#1.turn").write_text(f"LOGGEDOUT {iso(NOW - 800)} 4 - jsonl\n")
    rings, log = wake(tmp_path)
    assert len(rings) == 3 and len([x for x in log if "lo#1" in x]) == 1


# r993 — 카드 원천 «한 곳»: 명부 _cards_wt 가 있으면 그 워크트리 카드만 · 없으면 ROOT 만 · 정한 원천에 카드 없음 = 닫기 대기 아님(ring + 로그 1줄)
def root_card(tmp: Path, name: str, last: str) -> None:
    """ROOT 체크아웃의 옛 사본 — _cards_wt 가 있으면 판정은 이 사본을 «안» 본다."""
    d = tmp / "root/design/x/indices/진행"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.md").write_text(f"# {name}\n## 상태\n- 2026-10-24 — 대기→진행\n{last}\n\n## 정본\n- 없음\n", encoding="utf-8")


def rest_log(tmp: Path) -> list[str]:
    p = tmp / "root/.fable-team/state/card-rest.log"
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def test_r2_wt_card_wins_root_stale_copy(tmp_path):
    """r849 DA r2 반례 2 — ROOT 옛 사본 끝 = 완료 · 실제(=_cards_wt) 카드 끝 = 반송 → 일하는 나노는 ring 1."""
    (tmp_path / "root/.fable-team").mkdir(parents=True)
    (tmp_path / "r2#1.turn").write_text(f"IDLE {iso(NOW - 900)} 1000 - jsonl\n")
    card(tmp_path, "r2#1", "c-r2", "- DA⑥ r1 HOLD → 반송 r2")
    root_card(tmp_path, "c-r2", "세트: " + "c" * 40 + " · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0")
    queue(tmp_path, [(21, "r2#1")])
    rings, _ = wake(tmp_path)
    assert rings == ["ring r2#1 21"]  # ROOT 사본을 먼저 읽으면 ring 0 = FAIL


def test_r2b_wt_without_card_is_not_rest(tmp_path):
    """_cards_wt 가 있는데 그 워크트리에 카드가 없다(갓 spawn·이동 중) = 닫기 대기 아님 · ring 1 + 로그 1줄."""
    (tmp_path / "root/.fable-team").mkdir(parents=True)
    (tmp_path / "r2b#1.turn").write_text(f"IDLE {iso(NOW - 900)} 1000 - jsonl\n")
    card(tmp_path, "r2b#1", "c-r2b", "- 작업 중")
    (tmp_path / "root/.worktrees/wt-x/design/x/indices/완성/c-r2b.md").unlink()  # 그 워크트리에서 카드가 사라짐
    root_card(tmp_path, "c-r2b", "세트: " + "d" * 40 + " · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0")
    queue(tmp_path, [(22, "r2b#1")])
    rings, _ = wake(tmp_path)
    assert rings == ["ring r2b#1 22"]  # 조용한 «완료» 추정 0 · ROOT 사본도 안 본다
    assert len([x for x in rest_log(tmp_path) if "r2b#1" in x and "카드 없음" in x and "_cards_wt=wt-x" in x]) == 1


# api-outage(실측 출처): 로그아웃 좌석은 장애 시작·[재개] 0 — 재개하면 0초 실패 턴만 또 생긴다
def test_api_outage_never_resumes_logged_out(tmp_path):
    mbox = tmp_path / "mbox.sh"
    mbox.write_text(f'#!/bin/sh\necho "$2|$4" >> "{tmp_path}/m.log"\n')
    lo = write(tmp_path / "lo.jsonl", normal_turn(NOW - 900))
    ok = write(tmp_path / "ok.jsonl", normal_turn(NOW - 900))
    st = tmp_path / "st/api-outage.json"

    def run(now: int) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["python3", str(BIN / "ft_api_outage.py"), "--state", str(st), "--mbox", str(mbox), "--notify", "p#1", "--now", str(now)],
                              input=f"lo#1\t{lo}\nok#1\t{ok}\n", capture_output=True, text=True, timeout=30)
    assert run(NOW - 800).returncode == 0  # 기준선(오류 0)
    write(lo, error_turn(NOW - 120))
    assert run(NOW - 100).returncode == 0  # 로그아웃 오류 = 장애 시작 0
    write(ok, normal_turn(NOW - 30))
    r = run(NOW)  # 다른 좌석 정상 = 복구 꼴이어도 [재개] 0
    assert r.returncode == 0, r.stderr
    assert "SKIP 재개 lo#1 — 로그아웃 좌석" in r.stdout
    assert not (tmp_path / "m.log").exists(), (tmp_path / "m.log").read_text()


# ⓔ nano-close ③: 인증 실패 0초 턴을 뺀 마지막 기록 — 정상 턴 10분 전이면 통과 · 정상 턴 1분 전이면 지금처럼 반송
def gate(tmp: Path, f: Path) -> str:
    block = subprocess.run(["sed", "-n", r'/_lt="\$(/,/마지막 기록(/p', str(BIN / "ft-nano-close.sh")], capture_output=True, text=True).stdout
    assert block.count("\n") >= 4
    (tmp / "block.sh").write_text(block)
    r = subprocess.run(["bash", "-c", f'HERE="{BIN}"; f="{f}"; IDLE_MIN=3; bad=(); age=; . "{tmp}/block.sh"; printf "%s|" "${{bad[@]:-}}"'],
                       capture_output=True, text=True, timeout=30)
    return r.stdout


def test_e_nano_close_gate(tmp_path):
    now = int(time.time())  # 게이트는 실제 시계(date +%s)를 쓴다 — 모듈 NOW 는 긴 묶음 실행에서 몇 분 늙는다
    f = write(tmp_path / "lo.jsonl", normal_turn(now - 600) + error_turn(now - 90) + error_turn(now - 30))
    assert gate(tmp_path, f) == "|"  # 통과(반송 0)
    g = write(tmp_path / "busy.jsonl", normal_turn(now - 60))
    assert "③jsonl 마지막 기록" in gate(tmp_path, g)  # 회귀 0 — 일하는 좌석은 그대로 반송
    h = write(tmp_path / "mid.jsonl", error_turn(now - 600) + normal_turn(now - 60) + error_turn(now - 20))
    assert "③jsonl 마지막 기록" in gate(tmp_path, h)  # 실패 사이 정상 턴(1분 전)은 «활동»



# DA⑥ r1 ① — 정상 턴 뒤 인증 실패 600턴(>1MB) + 1턴: jsonl 창 상한 때문에 «첫 실패» 가 밀려도 쪽지 1통 · 프로세스를 다시 띄우면 1통 더
REAL_STATUS = '#!/bin/sh\ncase "$1" in\n  turn) [ "$2" = --file ] && exec bash "{real}" turn --file "$3"; exit 3;;\n  jsonl) [ -f "$FT_STUB/jsonl/$2.jsonl" ] && echo "$FT_STUB/jsonl/$2.jsonl" || exit 1;;\nesac\n'
PS = '#!/bin/sh\ncase "$*" in\n  *args=*) cat "$FT_STUB/ps";;\n  *lstart*) exit 1;;\nesac\n'


def real_world(tmp: Path) -> tuple[World, Path]:
    w = World(tmp)
    (w.stub / "real-status.sh").write_text(REAL_STATUS.replace("{real}", str(BIN / "ft-seat-status.sh")))
    (w.stub / "ps.sh").write_text(PS)
    (w.stub / "ps").write_text("500 %2 claude --resume x\n")  # t1-nano#0 = pane %2
    sess = tmp / "sess"
    sess.mkdir()
    (sess / "500.json").write_text(json.dumps({"pid": 500, "startedAt": 1792800000000}))
    w.env.update(FT_SEAT_STATUS=str(w.stub / "real-status.sh"), FT_SEATS_JSON="/nonexistent", FT_PS=str(w.stub / "ps.sh"), FT_CLAUDE_SESSIONS=str(sess))
    j = w.stub / "jsonl/t1-nano#0.jsonl"
    write(w.stub / "jsonl/t1-master#1.jsonl", normal_turn(NOW - 60))
    recs = normal_turn(NOW - 90000)
    for i in range(600):
        recs += error_turn(NOW - 80000 + i * 10, pad=2400)
    write(j, recs)
    assert j.stat().st_size > 1_500_000
    return w, sess


def sends(w: World) -> list[str]:
    return [x for x in w.mbox_log() if x.startswith("send|")]


def test_c_long_streak_over_tail_cap_one_notice(tmp_path):
    w, sess = real_world(tmp_path)
    j = w.stub / "jsonl/t1-nano#0.jsonl"
    first = turn(j)
    assert first[0] == "LOGGEDOUT"
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    write(j, error_turn(NOW - 70000, pad=2400))
    assert turn(j)[1] != first[1]  # 창 상한 때문에 «보이는 첫 실패» 가 밀렸다(DA 반례 그대로)
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1  # 같은 프로세스 = 0통 더
    (w.stub / "ps").write_text("600 %2 claude --resume x\n")  # 다시 띄움(새 pid)
    (sess / "600.json").write_text(json.dumps({"pid": 600, "startedAt": 1792900000000}))
    write(j, error_turn(NOW - 60000, pad=2400))
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1  # 재설계 r4 — 프로세스를 다시 띄운 것만으로는 구간이 안 끊긴다(키에 시작 시각 0)
    write(j, normal_turn(NOW - 300))  # 정상 턴(로그인 복구) = 구간 끝 → 칸 지움
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    write(j, error_turn(NOW - 60, pad=2400))  # 다시 로그아웃 = 새 구간 = 2통째
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 2


# DA⑥ r1 ③ — 첫 발신 rc1 → 칸 0 + 로그 1줄 → 다음 scan 에 1통
def test_c_send_failure_retries_next_scan(tmp_path):
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    (w.stub / "mbox.sh").write_text('#!/bin/sh\nif [ "$1" = send ] && [ -f "$FT_STUB/mbox.fail" ]; then rm -f "$FT_STUB/mbox.fail"; exit 1; fi\n'
                                    'for a; do last="$a"; done\n[ "$1" = send ] && echo "send|$2|$3|$last|$4" >> "$FT_STUB/mbox.log"\nexit 0\n')
    (w.stub / "mbox.fail").write_text("1")
    assert scan(w).returncode == 0 and not sends(w)
    assert any("act=l ERROR 발신 실패 rc=1" in x for x in w.scan_log())
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1


# ── 재설계 r4 — 쪽지 키 = 로그아웃 구간 칸 하나(프로세스 시작 시각·첫 실패 시각·pid 를 키에 안 씀 · DA⑥ r2 반례 1)
def test_r1_unreadable_process_start_one_notice(tmp_path):
    """ⓡ1 — DA⑥ r2 반례 1: 메타 {} ∧ ps lstart rc1(키 `500@?`) 뒤에 startedAt 이 복구돼도(키 `500@1792800000000`) 같은 로그아웃 = 쪽지 합 1통."""
    w, sess = real_world(tmp_path)
    (sess / "500.json").write_text("{}", encoding="utf-8")  # 세션 메타 못 읽음 ∧ ps lstart rc1(stub)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    (sess / "500.json").write_text(json.dumps({"pid": 500, "startedAt": 1792800000000}))  # 시작 시각이 «나중에 읽힘»
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1


def test_r1b_relogin_then_logout_two_notices_and_unreadable_scan_keeps_cell(tmp_path):
    """ⓡ1b — 로그아웃→정상→로그아웃 = 2통 · 사이에 못 읽은 scan 이 끼어도 그 구간은 1통."""
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    w.state("t1-nano#0", "UNKNOWN", 0)  # 상태 못 읽은 scan = 칸 그대로
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    w.state("t1-nano#0", "WORKING", 1)  # 정상 턴 = 칸 지움
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
    w.state("t1-nano#0", "LOGGEDOUT", 1)  # 다시 로그아웃 = 새 구간 = 2통째
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 2


def test_r3_cell_dir_unwritable_errors_then_retries(tmp_path):
    """ⓡ3 — 칸 폴더에 못 쓰면 ERROR 1줄 · 발신 0 · 풀린 뒤 다음 scan 에 1통."""
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    d = w.root / ".fable-team/state/stall"
    d.mkdir(parents=True)
    d.chmod(0o555)
    try:
        assert scan(w).returncode == 0 and not sends(w)
        assert any("act=l ERROR 상태 칸" in x for x in w.scan_log()), w.scan_log()
    finally:
        d.chmod(0o755)
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1


# ── 재설개 r3 — DA⑥ r3 HOLD 4건(소요 시간 검사 · 미완 턴 · 칸 폴더 · 기록 실패 2통)
def test_r4_slow_auth_failure_turn_is_not_logged_out(tmp_path):
    """ⓡ4 — DA⑥ r3 반례 1: 마지막 인증 실패 턴이 120초(durationMs=120000)면 «0초 실패» 가 아니다 → IDLE · nano-close ③ 은 최근 기록이라 반송."""
    ok = write(tmp_path / "quick.jsonl", normal_turn(NOW - 3600) + error_turn(NOW - 60))
    assert turn(ok)[0] == "LOGGEDOUT"  # 142ms 실측 꼴 = 그대로 로그아웃
    slow = write(tmp_path / "slow.jsonl", normal_turn(NOW - 3600) + error_turn(NOW - 60, duration_ms=120000))
    assert turn(slow)[0] == "IDLE"  # 일한 턴 — 로그아웃 아님
    assert "③jsonl 마지막 기록" in gate(tmp_path, slow)  # 활동으로 센다(최근 = 반송)
    assert gate(tmp_path, ok) == "|"  # 0초 실패만 있는 좌석은 지금처럼 면제


def test_r5_unfinished_turn_counts_as_activity(tmp_path):
    """ⓡ5 — DA⑥ r3 반례 2: 정상 턴 10분 전 + 30초 전 새 user·인증 실패 assistant(turn_duration 아직 없음) → 좌석 WORKING · nano-close ③ 반송."""
    recs = normal_turn(NOW - 600) + error_turn(NOW - 30)[:3]  # api-request·user·assistant 뿐(turn_duration 0)
    f = write(tmp_path / "wip.jsonl", recs)
    assert turn(f)[0] == "WORKING"
    assert "③jsonl 마지막 기록" in gate(tmp_path, f)  # 끝나지 않은 턴을 빼지 않는다


def test_r7_cell_written_before_send_one_notice(tmp_path):('#!/bin/sh\nfor a; do last="$a"; done\ncase "$1" in\n'
           '  send) n=$(ls "$FT_ROOT/.fable-team/state/stall" 2>/dev/null | grep -c "^logged-out[.]")\n'
           '    echo "send|$2|$3|$last|$4|cell=$n" >> "$FT_STUB/mbox.log";;\n  ring) echo "ring|$2|${3:-}" >> "$FT_STUB/mbox.log";;\nesac\n')


def test_r7_cell_written_before_send_one_notice(tmp_path):
    """ⓡ7 — DA⑥ r3 반례 4: 칸은 발신 «전»에 있다(발신 뒤 기록 실패로 같은 구간 2통 0) · 발신 성공 뒤 같은 구간은 0통."""
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    (w.stub / "mbox.sh").write_text(CELLNOW)
    assert scan(w).returncode == 0
    got = sends(w)
    assert len(got) == 1 and got[0].endswith("cell=1"), got  # 발신 시점에 칸이 이미 서 있다(발신 뒤 기록 = 0)
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1  # 같은 구간 = 0통 더
    assert not any("act=l ERROR" in x for x in w.scan_log()), w.scan_log()


def test_r7b_claim_write_failure_no_send(tmp_path):
    """ⓡ7b — 칸을 못 세우면(발신 전) 발신 0 + ERROR 1줄 · 자리가 풀리면 다음 scan 1통(중복 0)."""
    w = World(tmp_path)
    w.state("t1-master#1", "WORKING", 0)
    w.state("t1-nano#0", "LOGGEDOUT", 30)
    d = w.root / ".fable-team/state/stall"
    d.mkdir(parents=True)
    cell = d / "logged-out.t1-nano#0"
    cell.mkdir()  # 자리에 폴더 = 칸을 못 세운다
    assert scan(w).returncode == 0 and not sends(w)
    assert any("act=l ERROR 칸" in x for x in w.scan_log())
    cell.rmdir()
    w.advance(900)
    assert scan(w).returncode == 0 and len(sends(w)) == 1
