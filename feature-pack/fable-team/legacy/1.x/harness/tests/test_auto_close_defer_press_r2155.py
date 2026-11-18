"""r2155 — 승계 뒤 옛 좌석 자동 닫기 두 길도 ft-seat-close 에 --defer-press 를 넘긴다(r2153 = retire 길만).

① succ-close 후보 1석 · FT_SUCC_AUTO_CLOSE=1 → 가짜 close argv = <옛> --reason «승계 끝 자동 닫기 → <새>» --defer-press (A1)
② keeper B3 닫기 조건 충족 1석 → close argv 끝에 --defer-press 1개 · --seats 그대로 (A2)
③ 꺼짐 → close 호출 0 · «(꺼짐)» 줄 그대로 (A1 · 기준판도 Green)
④ 실 ft-seat-close + press 진행 + pane 자손 nohup 러너 · succ-close 길 → 러너 생존(ps) · reap-defer 줄(close raw 출력) · 미룸 파일 (A1)
변이 M1(succ-close argv 의 --defer-press 지움 → ① ④ FAIL) · M2(keeper argv → ② FAIL) · 변이마다 원본 판 같은 사례 1회 더(반대 결과 대조).
격리: ①~③ = 임시 루트 · 스텁 tmux/close · ④ = r1568 픽스처(임시 폴더 · 이 회차 tmux 세션 · 표식 러너 정리) · 실 좌석 · 실 press 0.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
BIN = HERE.parent / "kit/fable-team/bin"
FT2 = HERE.parents[3] / "ft2"
FIX = HERE / "test_seat_close_confirm_r1568_fixtures.sh"
SC_OLD, SC_NEW = '"--defer-press"], None, 25, cwd=root)', "], None, 25, cwd=root)"
KC_OLD, KC_NEW = '"--seats", path, "--defer-press"]', '"--seats", path]'


def _mod(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, str(path))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


r1757 = _mod(HERE / "test_succ_auto_close_r1757.py", "r1757_for_r2155")
kw = _mod(FT2 / "tests" / "keeper_world_r1812.py", "keeper_world_r2155")


def _scan(bin_dir: Path):
    """bin_dir 의 ft_stall_scan 을 맨 앞 경로로 다시 import(원본 ↔ 변이 사본 오감)."""
    while str(bin_dir) in sys.path:
        sys.path.remove(str(bin_dir))
    sys.path.insert(0, str(bin_dir))
    for mod in ("ft_stall_scan", "ft_seat_succ_close", "ft_stall_detect"):
        sys.modules.pop(mod, None)
    import ft_stall_scan as m  # noqa: PLC0415

    return m


def _world(tmp: Path, mp) -> "r1757.World":
    w = r1757.World(tmp)
    r1757._stub(w.tm / "tmux.sh", r1757.TMUX_STUB)
    mp.setenv("TM_DIR", str(w.tm))
    mp.setenv("HOME", str(tmp / "home"))
    mp.delenv("ZC_RESUME_DIR", raising=False)
    mp.delenv("TMUX_PANE", raising=False)
    mp.delenv("FT_SUCC_RETRY_S", raising=False)
    mp.setenv("STUB_CALLS", str(w.calls))
    mp.setenv("FT_SEAT_CLOSE_BIN", str(r1757._stub(tmp / "close.sh", r1757.CLOSE_STUB)))
    mp.setenv("FT_SUCC_AUTO_CLOSE", "1")
    return w


def c1(tmp: Path, mp, bin_dir: Path = BIN) -> None:
    w = _world(tmp, mp)
    w.pair("byz-x-tester#1", "byz-x-tester#2")
    out = w.scan(_scan(bin_dir)).succ_close("T")
    assert w.calls.read_text().splitlines() == ["byz-x-tester#1 --reason 승계 끝 자동 닫기 → byz-x-tester#2 --defer-press"], out
    assert out == ["T succ-close byz-x-tester#1 rc=0 — CLOSED-SESSION byz-x-tester#1 stub"], out


def c2(tmp: Path, mp, ft2: Path = FT2) -> None:
    w = kw.World(tmp, mp, ft2)
    old, new = "byz-harness-nano-x-r1#0", "byz-harness-nano-x-r1#1"
    path = w.root / ".fable-team" / "seats-harness.json"
    kw._put(path, {"_master": "M", old: {"_replaced_by": new}})
    k, calls = w.keeper(), []

    def call(argv, timeout=7, retry=0):
        calls.append(argv)
        return (0, old + "\n", "") if argv[1] == "list-sessions" else (0, "STUB", "") if argv[0] == "bash" else (1, "", "?")

    k.call, k.look, k.idle = call, (lambda *a, **kv: "REST"), (lambda *a, **kv: True)
    assert k.retired() is None
    closes = [a for a in calls if a[0] == "bash"]
    assert closes == [["bash", k.close_bin, old, "--reason", "retire -> " + new, "--seats", str(path), "--defer-press"]], calls
    assert [x for x in k.lines if x.startswith("CLOSED-SEAT")], k.lines


def c3(tmp: Path, mp, bin_dir: Path = BIN) -> None:
    w = _world(tmp, mp)
    w.pair("byz-x-tester#1", "byz-x-tester#2")
    mp.delenv("FT_SUCC_AUTO_CLOSE")
    out = w.scan(_scan(bin_dir)).succ_close("T")
    assert w.n_calls() == 0 and out == ["T succ-close 후보 byz-x-tester#1 → byz-x-tester#2 (꺼짐)"], out


C4 = r'''# c4 <fixtures> <bin> — 옛 좌석(pane 자손 nohup press 러너) · 후계 세션 · 명부 stop-ready+_replaced_by · 재개 기록 → succ_close 1회(실 tmux · 실 close)
source "$1"; B="$2"; PY="$3"
export FT_ROOT="$TMP/root" FT_ALLOW_TRACKED_BIN=1 FT_SUCC_AUTO_CLOSE=1 FT_PRESS_RUNNER_RE='tests/e2e/r2155_press_fx\.py'
mkdir -p "$FT_ROOT/.fable-team" "$TMP/tests/e2e" "$TMP/state"; git -C "$FT_ROOT" init -q; mkfifo "$TMP/sess.fifo" "$TMP/sess.$$.fifo"
printf 'import time\nwhile True: time.sleep(0.2)\n' > "$TMP/tests/e2e/r2155_press_fx.py"
printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "stop-ready", "agent": "claude", "model": "m", "tick": null, "_replaced_by": "%s"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$S" "$S1" "$S1" > "$FT_ROOT/.fable-team/seats.json"
: > "$ZC_RESUME_DIR/$S.json"; mksess "$S1" "$TMP/wt"
tmux new-session -d -s "$S" -c "$TMP/wt" -e "FT_SEAT=$S" "$BASH_X" -c "nohup python3 '$TMP/tests/e2e/r2155_press_fx.py' '$MKX-$S' </dev/null >/dev/null 2>&1 & while kill -0 $TEST_PID 2>/dev/null; do read -t 0.2 _ <> '$TMP/sess.fifo' || :; done"
for i in 1 2 3 4 5 6 7 8 9 10; do R="$(pgrep -f "fx\.py $MKX-$S" | head -1)"; [ -n "$R" ] && break; sleep 0.05; done
[ -n "${R:-}" ] || { echo "판정 불가 러너 픽스처 없음"; exit 9; }
printf '#!/usr/bin/env bash\no="$(bash %q "$@" 2>&1)"; r=$?; printf "%%s\\n" "$*" >> %q; printf "%%s\\n" "$o" | tee -a %q; exit $r\n' "$B/ft-seat-close.sh" "$TMP/argv" "$TMP/raw" > "$TMP/close-tee.sh"
sum="$(cd "$B" && env -u TMUX_PANE FT_SEAT_CLOSE_BIN="$TMP/close-tee.sh" "$PY" -c 'import sys,time;from pathlib import Path;import ft_seat_succ_close as s;from ft_stall_detect import run;print("\n".join(s.succ_close(Path(sys.argv[1]),Path(sys.argv[2]),time.time(),["tmux"],run,"T",Path("."))))' "$FT_ROOT" "$TMP/state" 2>&1)"
wait_dead "$MKX-$S"
ps -o command= -p "$R" 2>/dev/null | grep -q "fx\.py $MKX" && L=alive || L=dead
tmux has-session -t "=$S" 2>/dev/null && U=up || U=gone
D=0; grep -q "reap-defer pid=$R why=press-active" "$TMP/raw" 2>/dev/null && D=1
echo "R $(grep -c ' rc=0 ' <<< "$sum") $L $U $D $([ -f "$FT_REAP_DEFER_DIR/$S.jsonl" ] && echo file || echo nofile)"
echo "SUM $sum"; echo "ARGV $(cat "$TMP/argv" 2>/dev/null)"; sed 's/^/RAW /' "$TMP/raw" 2>/dev/null
kill -9 "$R" 2>/dev/null; :
'''


def c4(tmp: Path, mp, bin_dir: Path = BIN) -> None:
    if not shutil.which("tmux"):
        pytest.skip("판정 불가 tmux 없음(④ 실 세션 사례)")
    (tmp / "c4.sh").write_text(C4, encoding="utf-8")
    p = subprocess.run(["bash", str(tmp / "c4.sh"), str(FIX), str(bin_dir), sys.executable], capture_output=True, text=True, timeout=60)
    head = next((x for x in p.stdout.splitlines() if x.startswith("R ")), "")
    if p.returncode != 0 or not head:
        pytest.fail(f"판정 불가 ④ 픽스처 rc={p.returncode} — {p.stdout[-600:]} {p.stderr[-400:]}")
    assert head == "R 1 alive gone 1 file", p.stdout   # rc=0 줄 1 · 러너 생존 · 옛 세션 닫힘 · reap-defer 줄 · 미룸 파일


CASES = {"①": c1, "②": c2, "③": c3, "④": c4}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch)


def _mutant(src: Path, dst: Path, rel: str, old: str, new: str) -> Path:
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (dst / rel).read_text(encoding="utf-8")
    if text.count(old) == 0 and "--defer-press" not in text:
        pytest.skip(f"이 판에 --defer-press 없음(기준판) — {rel}")
    assert text.count(old) == 1, (rel, old)
    (dst / rel).write_text(text.replace(old, new), encoding="utf-8")
    return dst


@pytest.mark.parametrize("case", ["①", "④"])
def test_m1_succ_close_flag_dropped(case, tmp_path, monkeypatch):
    mb = _mutant(BIN, tmp_path / "mb", "ft_seat_succ_close.py", SC_OLD, SC_NEW)
    (tmp_path / "w1").mkdir(), (tmp_path / "w2").mkdir()
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", monkeypatch, mb)
    CASES[case](tmp_path / "w2", monkeypatch)   # 원본 대조 = 같은 사례 통과


def test_m2_keeper_flag_dropped(tmp_path, monkeypatch):
    tree = _mutant(FT2, tmp_path / "m" / "ft2", "adapters/pi/keeper_close.py", KC_OLD, KC_NEW)
    (tmp_path / "w1").mkdir(), (tmp_path / "w2").mkdir()
    with pytest.raises(AssertionError):
        c2(tmp_path / "w1", monkeypatch, tree)
    c2(tmp_path / "w2", monkeypatch)   # 원본 대조
