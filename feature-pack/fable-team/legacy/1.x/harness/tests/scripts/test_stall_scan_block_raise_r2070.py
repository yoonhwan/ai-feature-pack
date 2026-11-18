"""r2070 — 주기 점검 도구(ft_stall_scan 세 함수 · ft_teamset check_team)가 로그에만 남기던 줄을 막힘 장부(block.sh)에 올린다.

① lib 인자·env·호출 0 갈래·원인 글 자름  ② lib rc≠0·멈춤(상한 + 남은 호출 0)
③ record_notify  ④ auto_close close-due  ⑤ auto_close_da_arch «제외»·close-due  ⑥ auto_close 실패 줄
⑦ auto_close_da_arch 실패 줄  ⑧ check_team 순번 큐  ⑨ 불변(장부 없음 = 스텁 = 멈춘 스텁)  ⑩ block.sh 인자 문법
격리: 장부 = FT_BLOCK_BIN 스텁(인자·FT20_SCAN_ROOT 를 파일에 적음) · 닫기·목록·알림 = env 스텁 · 임시 루트 · 실 tmux·실 장부·발신 0 · sleep 0(멈춤 = fifo 읽기).
"""
from __future__ import annotations

import json
import os
import stat
import sys
import threading
import time
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R2070_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
NOW = 1_800_000_000.0
STAMP = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(NOW))

BLK = r'''#!/usr/bin/env bash
[ -n "${BLK_FIFO:-}" ] && read -r _ < "$BLK_FIFO"
exec python3 - "$@" <<'PY'
import json, os, sys
a = sys.argv[1:]
def ok(a):   # block.sh 인자 규칙(raise = 도구 · seat|card|team · 대상 · --cause · --fix · 선택 --period 숫자) + 빈 칸 0
    if a[:1] != ["raise"] or len(a) < 4 or a[2] not in ("seat", "card", "team") or not a[1] or not a[3]:
        return False
    rest, opt = a[4:], {}
    while rest:
        if len(rest) < 2 or rest[0] not in ("--cause", "--fix", "--period"):
            return False
        opt[rest[0]] = rest[1]; rest = rest[2:]
    return bool(opt.get("--cause")) and bool(opt.get("--fix")) and (opt.get("--period") or "0").isdigit()
good = ok(a)
with open(os.environ["BLK_CALLS"], "a", encoding="utf-8") as f:
    f.write(json.dumps({"args": a, "root": os.environ.get("FT20_SCAN_ROOT"), "ok": good}, ensure_ascii=False) + "\n")
if os.environ.get("BLK_ERR"):
    sys.stderr.write(os.environ["BLK_ERR"] + "\n")
sys.exit(int(os.environ.get("BLK_RC") or (0 if good else 2)))
PY
'''


def _stub(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _fresh(name: str):
    if str(BIN) not in sys.path:
        sys.path.insert(0, str(BIN))
    for k in ("ft_block", name):
        sys.modules.pop(k, None)
    return __import__(name)


def _calls(f: Path) -> list[dict]:
    return [json.loads(x) for x in f.read_text(encoding="utf-8").splitlines()] if f.exists() else []


@pytest.fixture()
def blk(tmp_path, monkeypatch):
    calls = tmp_path / "blk-calls.jsonl"
    stub = tmp_path / "blk.sh"
    stub.write_text(BLK, encoding="utf-8")
    monkeypatch.setenv("BLK_CALLS", str(calls))
    for k in ("FT_BLOCK_BIN", "FT_CRITICAL_OFF", "BLK_FIFO", "BLK_RC", "BLK_ERR", "FT_NANO_AUTO_CLOSE", "FT_SEAT_AUTO_CLOSE_DA_ARCH"):
        monkeypatch.delenv(k, raising=False)
    return stub, calls


# ---------- ① · ② lib ----------
def test_1_lib_args_env_and_noop(tmp_path, blk, monkeypatch):
    stub, calls = blk
    root = tmp_path / "root"
    root.mkdir()
    lib = _fresh("ft_block")
    lib.block(root, "raise", "t", "seat", "s", "--cause", "c", "--fix", "f")
    assert calls.exists() is False, "FT_BLOCK_BIN 없음 ∧ block.sh 없음 = 호출 0"
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    assert lib.block(root, "raise", "t", "seat", "s", "--cause", "c", "--fix", "f") is None
    got = _calls(calls)
    assert [c["args"] for c in got] == [["raise", "t", "seat", "s", "--cause", "c", "--fix", "f"]] and got[0]["root"] == str(root), got
    monkeypatch.setenv("FT_CRITICAL_OFF", "1")
    lib.block(root, "raise", "t", "seat", "s", "--cause", "c", "--fix", "f")
    assert len(_calls(calls)) == 1, "FT_CRITICAL_OFF=1 = 호출 0"
    monkeypatch.delenv("FT_CRITICAL_OFF")
    lib.block(root, "raise", "t", "seat", "s", "--cause", "x" * 200, "--fix", "f")
    lib.block(root, "raise", "t", "seat", "s", "--cause", "첫 줄\n둘째 줄", "--fix", "f")
    got = _calls(calls)
    assert got[1]["args"][5] == "x" * 160 and got[2]["args"][5] == "첫 줄", got
    lib.block(tmp_path / "없는-루트", "raise", "t", "seat", "s", "--cause", "c", "--fix", "f")
    assert len(_calls(calls)) == 3, "데이터 루트 없음 = 호출 0"
    monkeypatch.delenv("FT_BLOCK_BIN")
    (root / ".fable-team/state/ft20-r1483-watch").mkdir(parents=True)
    (root / ".fable-team/state/ft20-r1483-watch/block.sh").write_text(BLK, encoding="utf-8")
    lib.block(root, "raise", "t", "team", "x", "--cause", "c", "--fix", "f")
    assert len(_calls(calls)) == 4, "FT_BLOCK_BIN 없음 = <루트>/…/block.sh"


def test_2_lib_fail_and_hang(tmp_path, blk, monkeypatch, capfd):
    stub, calls = blk
    root = tmp_path / "root"
    root.mkdir()
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    lib = _fresh("ft_block")
    monkeypatch.setenv("BLK_RC", "9")
    monkeypatch.setenv("BLK_ERR", "장부-오류-글-r2070")
    lib.block(root, "raise", "t", "seat", "s", "--cause", "c", "--fix", "f")
    assert len(_calls(calls)) == 1 and "장부-오류-글-r2070" not in capfd.readouterr().err
    monkeypatch.delenv("BLK_RC")
    fifo = tmp_path / "hang.fifo"
    os.mkfifo(fifo)
    monkeypatch.setenv("BLK_FIFO", str(fifo))
    t0 = time.monotonic()
    th = threading.Thread(target=lib.block, args=(root, "raise", "t", "seat", "s", "--cause", "c", "--fix", "f"), daemon=True)
    th.start()
    th.join(lib.LIMIT_S + 2 if hasattr(lib, "LIMIT_S") else 9)
    stuck = th.is_alive()
    if not stuck:
        lib.block(root, "raise", "t", "seat", "s2", "--cause", "c", "--fix", "f")
    try:   # 시험 끝에 fifo 닫음 — 멈춘 스텁이 남아 있으면 풀어 준다
        fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
        os.write(fd, b"x\n")
        os.close(fd)
    except OSError:
        pass
    th.join(5)
    assert not stuck and time.monotonic() - t0 < 7 + 2 + 5, "멈춘 장부 = 상한 + 2초 안에 돌아옴"
    assert len(_calls(calls)) == 1, "상한을 넘긴 뒤 같은 실행의 다음 block = 호출 0"


# ---------- 사례(③~⑧) — 한 사례 = (스텁 놓기 → 함수 부르기 → 관찰) ----------
def _scan(m, root: Path):
    o = object.__new__(m.Scan)
    o.root, o.state_dir, o.now = root, root / "state", NOW
    o.state_dir.mkdir(parents=True, exist_ok=True)
    return o


def _tool_calls(root: Path) -> str:
    f = root / "tool-calls.txt"
    return f.read_text(encoding="utf-8") if f.exists() else ""


def _states(root: Path) -> dict:
    return {p.name: p.read_text(encoding="utf-8") for p in sorted((root / "state").glob("*.json"))} if (root / "state").is_dir() else {}


def _rec(root: Path, name: str, lines: list[str], rc: int | str) -> Path:
    body = 'printf "%s\\n" "$*" >> "' + str(root / "tool-calls.txt") + '"\n' + "".join(f"printf '%s\\n' \"{ln}\"\n" for ln in lines) + f"exit {rc}\n"
    return _stub(root / "stubs" / name, body)


def _approve(seat: str, head: str) -> str:
    return f"닫기 차례 {seat} 팀=harness 갈래=승인 set={head} main=abc123456 — bash ft-nano-close.sh {seat} --approved /tmp/da.md --result /tmp/r.md --recv 7"


def c_rn99(root, mp):
    mp.setenv("FT_NANO_RECORD", str(_rec(root, "rec.sh", [], 99)))
    return [_scan(_fresh("ft_stall_scan"), root).record_notify(STAMP)]


def c_rn0(root, mp):
    mp.setenv("FT_NANO_RECORD", str(_rec(root, "rec.sh", [], 0)))
    return [_scan(_fresh("ft_stall_scan"), root).record_notify(STAMP)]


def c_ac_due9(root, mp):
    mp.setenv("FT_NANO_AUTO_CLOSE", "1")
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [], 9)))
    return [_scan(_fresh("ft_stall_scan"), root).auto_close()]


def c_ac_empty(root, mp):
    mp.setenv("FT_NANO_AUTO_CLOSE", "1")
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [], 0)))
    return [_scan(_fresh("ft_stall_scan"), root).auto_close()]


def c_ac_off(root, mp):
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [], 9)))
    return [_scan(_fresh("ft_stall_scan"), root).auto_close()]


def _ac_fail(root, mp, rc, first):
    mp.setenv("FT_NANO_AUTO_CLOSE", "1")
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [_approve("byz-h-x#0", "S1")], 0)))
    mp.setenv("FT_NANO_CLOSE", str(_rec(root, "close.sh", [first], rc)))
    o = _scan(_fresh("ft_stall_scan"), root)
    one = o.auto_close()
    calls_after_one = _tool_calls(root)
    return [one, calls_after_one, o.auto_close()]   # 둘째 판 = 같은 HEAD


def c_ac_held3(root, mp):
    return _ac_fail(root, mp, 3, "HELD byz-h-x#0 승인 기록 없음")


def c_ac_rej1(root, mp):
    return _ac_fail(root, mp, 1, "REJECT byz-h-x#0 미커밋")


def c_ac_closed(root, mp):
    mp.setenv("FT_NANO_AUTO_CLOSE", "1")
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [_approve("byz-h-x#0", "S1")], 0)))
    mp.setenv("FT_NANO_CLOSE", str(_rec(root, "close.sh", ["CLOSED byz-h-x#0 approved=1 set=S1"], 0)))
    return [_scan(_fresh("ft_stall_scan"), root).auto_close()]


class _Ctx:   # 착지기록 갈래의 명부·장부 조회 대역(역할 nano · 조상 확인 통과)
    def __init__(self, root):
        self.root = root

    def seats(self, _team):
        return {"byz-h-l#0": {"role": "nano"}, "_master": "byz-h-master-pi#1"}


def c_ac_land1(root, mp):
    m = _fresh("ft_stall_scan")
    nra = sys.modules["ft_nano_record_auto"]
    mp.setattr(nra, "Ctx", _Ctx)
    mp.setattr(nra, "ancestor", lambda *_a: "")
    mp.setenv("FT_NANO_AUTO_CLOSE", "1")
    ln = "닫기 차례 byz-h-l#0 팀=harness 갈래=착지기록 set=S1 rec=R1 main=abc — bash ft-nano-close.sh byz-h-l#0 --landed-pr 5 --result /tmp/r.md --recv 7"
    mp.setenv("FT_NANO_CLOSE_DUE", str(_rec(root, "due.sh", [ln], 0)))
    mp.setenv("FT_NANO_CLOSE", str(_rec(root, "close.sh", ["REJECT byz-h-l#0 착지 확인 실패"], 1)))
    return [_scan(m, root).auto_close()]


EXCL = ["제외 s1 미커밋 3줄", "제외 s2 미답 발주 #7", "제외 s3 받을 일 발주 1", "제외 s4 상태 BUSY (IDLE 아님)", "제외 s5 유휴 5분 < 문턱"]


def _da(root, mp, lines, rc, close_first="", close_rc=0):
    mp.setenv("FT_SEAT_AUTO_CLOSE_DA_ARCH", "1")
    body = ('printf "%s\\n" "$*" >> "' + str(root / "tool-calls.txt") + '"\n'
            + f'if [ "${{1:-}}" = --close ]; then printf "%s\\n" "{close_first}"; exit {close_rc}; fi\n'
            + "".join(f"printf '%s\\n' \"{ln}\"\n" for ln in lines) + f"exit {rc}\n")
    mp.setenv("FT_SEAT_CLOSE_DUE", str(_stub(root / "stubs" / "sdue.sh", body)))
    o = _scan(_fresh("ft_stall_scan"), root)
    one = o.auto_close_da_arch(STAMP)
    return [one, _tool_calls(root), o.auto_close_da_arch(STAMP)]


def c_da_excl(root, mp):
    return _da(root, mp, EXCL, 0)


def c_da_due9(root, mp):
    return _da(root, mp, [], 9)


def c_da_off(root, mp):
    mp.setenv("FT_SEAT_CLOSE_DUE", str(_rec(root, "sdue.sh", EXCL, 9)))
    return [_scan(_fresh("ft_stall_scan"), root).auto_close_da_arch(STAMP)]


SIX = "닫기 차례 s6 갈래=유휴(arch) end=1799990000 idle=40"


def c_da_fail1(root, mp):
    return _da(root, mp, [SIX], 0, "CLOSE-FAIL s6 tmux", 1)


def c_da_rc3(root, mp):
    return _da(root, mp, [SIX], 0, "판정 불가 s6 tmux", 3)


def _ts(root, mp, missing: int):
    mp.setenv("FT_TEAMSET_NOTIFY", "0")
    ts = _fresh("ft_teamset")
    q = root / ".fable-team/state/spawn-queue-alpha.tsv"
    q.parent.mkdir(parents=True, exist_ok=True)
    live_card = root / "cards/대기/ok.md"
    live_card.parent.mkdir(parents=True, exist_ok=True)
    live_card.write_text("x", encoding="utf-8")
    rows = [f"{live_card}\t0"] + [f"{root}/cards/대기/gone{i}.md\t0" for i in range(missing)]
    q.write_text("".join(r + "\n" for r in rows), encoding="utf-8")
    spec = {"default": 3, "teams": {"alpha": 3}, "arch": set(), "keys": set(), "role_model": {}}
    roster = {"team": "alpha", "diag": "OK", "doc": {"_master": "byz-alpha-master-claude#1"}}
    return [ts.check_team(spec, str(root), "alpha", ["byz-alpha-master-claude#1"], roster, None), q.read_text(encoding="utf-8").replace(str(root), "<R>")]


def c_ts2(root, mp):
    return _ts(root, mp, 2)


def c_ts0(root, mp):
    return _ts(root, mp, 0)


S1, NAC = "byz-h-x#0", "판정 필요 byz-h-x#0 닫기 — 원인을 고친 뒤 ft-nano-close.sh 손 실행(같은 HEAD 는 자동 재시도 0)"
# 사례 → 기대 장부 호출(인자 목록 · None 칸 = 그 자리의 원인 글은 앞머리만 본다)
CASES = {
    "rn99": (c_rn99, [["raise", "ft-stall-scan", "team", "record-notify", "--cause", "판정 불가 record-notify rc=99",
                       "--fix", "판정 필요 정리 차례 알림 — ft-nano-record.sh notify 손 실행으로 rc·출력 확인", "--period", "150"]]),
    "rn0": (c_rn0, []),
    "ac_due9": (c_ac_due9, [["raise", "ft-stall-scan", "team", "nano-auto-close", "--cause", "판정 불가 auto-close close-due rc=9 — 닫기 0",
                             "--fix", "판정 필요 닫기 차례 목록 — ft-nano-close-due.sh --all 손 실행", "--period", "150"]]),
    "ac_empty": (c_ac_empty, []),
    "ac_off": (c_ac_off, []),
    "ac_held3": (c_ac_held3, [["raise", "ft-nano-close", "seat", S1, "--cause", f"auto-close 실패 {S1} rc=3 — HELD byz-h-x#0 승인 기록 없음", "--fix", NAC]]),
    "ac_rej1": (c_ac_rej1, [["raise", "ft-nano-close", "seat", S1, "--cause", f"auto-close 실패 {S1} rc=1 — REJECT byz-h-x#0 미커밋", "--fix", NAC]]),
    "ac_closed": (c_ac_closed, []),
    "ac_land1": (c_ac_land1, [["raise", "ft-nano-close", "seat", "byz-h-l#0", "--cause", "auto-close 실패 byz-h-l#0 rc=1 갈래=착지기록 — REJECT byz-h-l#0 착지 확인 실패",
                               "--fix", "판정 필요 byz-h-l#0 닫기 — 원인을 고친 뒤 ft-nano-close.sh 손 실행(같은 HEAD 는 자동 재시도 0)"]]),
    "da_excl": (c_da_excl, [["raise", "ft-stall-scan", "seat", s, "--cause", ln, "--fix", f"판정 필요 {s} — 미커밋·미답 발주·받을 일을 끝낸 뒤 닫기", "--period", "150"]
                            for s, ln in (("s1", EXCL[0]), ("s2", EXCL[1]), ("s3", EXCL[2]))] * 2),   # 매 판 다시 보는 줄 = 두 판 모두
    "da_due9": (c_da_due9, [["raise", "ft-stall-scan", "team", "seat-auto-close", "--cause", "판정 불가 seat-auto-close close-due rc=9 — 닫기 0",
                             "--fix", "판정 필요 닫기 차례 목록 — ft-seat-close-due.sh 손 실행", "--period", "150"]] * 2),
    "da_off": (c_da_off, []),
    "da_fail1": (c_da_fail1, [["raise", "ft-seat-close", "seat", "s6", "--cause", "seat-auto-close 실패 s6 rc=1 — CLOSE-FAIL s6 tmux",
                               "--fix", "판정 필요 s6 닫기 — 원인을 고친 뒤 ft-seat-close-due.sh --close s6 손 실행"]]),
    "da_rc3": (c_da_rc3, []),
    "ts2": (c_ts2, [["raise", "ft-teamset", "team", "alpha", "--cause", "큐 확인 필요 2(카드 없음·명부 행 없음)",
                     "--fix", "판정 필요 alpha 순번 큐 — 큐 파일의 없는 카드 줄 정리", "--period", "900"]]),
    "ts0": (c_ts0, []),
}


def _observe(case, base: Path, mode: str, blk, mp, capfd):
    """한 사례를 한 모드(none = 장부 없음 · stub · hang = 멈춘 스텁)로 1회 — 관찰 = 반환 · stdout · stderr · 상태 파일 · 도구 호출 기록."""
    stub, calls = blk
    root = base / mode
    root.mkdir()
    mp.delenv("FT_BLOCK_BIN", raising=False)
    mp.delenv("BLK_FIFO", raising=False)
    if mode != "none":
        mp.setenv("FT_BLOCK_BIN", str(stub))
    if mode == "hang":
        fifo = base / "hang.fifo"
        os.mkfifo(fifo)
        mp.setenv("BLK_FIFO", str(fifo))
    _ = capfd.readouterr()
    ret = CASES[case][0](root, mp)
    out = capfd.readouterr()
    obs = json.loads(json.dumps([ret, out.out, out.err, _states(root), _tool_calls(root)], ensure_ascii=False))
    return obs


@pytest.mark.parametrize("case", list(CASES))
def test_3_to_10_cases(case, tmp_path, blk, monkeypatch, capfd):
    """③~⑧ 기대 장부 호출 · ⑨ 장부 없음 = 스텁 = 멈춘 스텁 관찰 같음 · ⑩ 모든 호출이 block.sh 인자 규칙 통과."""
    _stub_, calls = blk
    none = _observe(case, tmp_path, "none", blk, monkeypatch, capfd)
    assert not calls.exists(), "장부 없음 = 호출 0"
    stubbed = _observe(case, tmp_path, "stub", blk, monkeypatch, capfd)
    got = _calls(calls)
    assert [c["args"] for c in got] == CASES[case][1], json.dumps(got, ensure_ascii=False, indent=1)
    assert all(c["ok"] and c["root"] == str(tmp_path / "stub") for c in got), got   # ⑩
    assert stubbed == none, "⑨ 스텁 장부 = 장부 없음"
    calls.unlink(missing_ok=True)
    hung = _observe(case, tmp_path, "hang", blk, monkeypatch, capfd)
    assert not calls.exists(), "멈춘 스텁은 적기 전에 멈춘다"
    assert hung == none, "⑨ 멈춘 장부 = 장부 없음"


def test_3_record_notify_returns_line(tmp_path, blk, monkeypatch):
    stub, calls = blk
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    assert c_rn99(tmp_path, monkeypatch) == [[f"{STAMP} 판정 불가 record-notify rc=99 — 멎은 곳: 표식 없음"]]   # r2175 N6


def test_6_same_head_no_close_no_block(tmp_path, blk, monkeypatch):
    stub, calls = blk
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    one, calls_one, two = c_ac_rej1(tmp_path, monkeypatch)
    assert any("auto-close 실패" in x for x in one) and two == [], (one, two)
    assert calls_one.count("--approved") == 1 and _tool_calls(tmp_path).count("--approved") == 1, "같은 HEAD = 닫기 0"
    assert len(_calls(calls)) == 1, "같은 HEAD = 장부 호출 0(앞 판 줄 유지)"


def test_7_same_end_no_close_no_block(tmp_path, blk, monkeypatch):
    stub, calls = blk
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    one, calls_one, two = c_da_fail1(tmp_path, monkeypatch)
    assert calls_one.count("--close") == 1 and _tool_calls(tmp_path).count("--close") == 1, "같은 end = --close 0"
    assert len(_calls(calls)) == 1


def test_8_warn_text_kept(tmp_path, blk, monkeypatch):
    stub, _calls_ = blk
    monkeypatch.setenv("FT_BLOCK_BIN", str(stub))
    (st, msg), _q = c_ts2(tmp_path, monkeypatch)
    assert st == "WARN" and "큐 확인 필요 2(카드 없음·명부 행 없음)" in msg, msg
