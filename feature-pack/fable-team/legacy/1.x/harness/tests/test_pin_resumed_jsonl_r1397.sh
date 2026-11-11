#!/usr/bin/env bash
# test_pin_resumed_jsonl_r1397.sh — r1397: 재부팅 복구가 --resume U 로 띄운 claude 좌석도 ① 짚기에서 바로 jsonl 을 짚는다
#   카드 반례 J1~J5(--resume=U · -r U 포함) · 변이 2 · bin=kit 같은 내용
# 격리: 가짜 ps·tmux(파일 대역) + 임시 projects 폴더 · 실 ps·실 tmux·실 ~/.claude 0 · 자기 재호출 0(변이는 bin 사본을 돌린다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

# probe.py — J1~J5 를 한 번에 돌리고 PASS/FAIL 줄 + rc 로 낸다. argv1 = import 할 bin 폴더 · argv2 = 세계 폴더
cat > "$T/probe.py" <<'EOPY'
import os
import re
import sys
import time
from pathlib import Path

BIN = Path(sys.argv[1])
sys.path.insert(0, str(BIN))
import ft_api_outage_util as ut  # noqa: E402

CWD_A = "/tmp/r1397/wt-a"
U1 = "11111111-2222-3333-4444-555555555555"   # 파일이 있는 세션 id
U9 = "99999999-8888-7777-6666-555555555555"   # argv 에는 있는데 파일이 없는 세션 id
ROOT = Path(sys.argv[2])
TMUX = '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) cat "$PANE_FILE" ;;\n  list-sessions) cat "$PID_FILE" ;;\n  *) exit 1 ;;\nesac\n'
PS = '#!/usr/bin/env bash\ncat "$PS_FILE"\n'

reads: list[str] = []
stats: list[str] = []
_open, _stat = Path.open, Path.stat


def spy_open(self, mode="r", *a, **k):
    if "b" in str(mode) and str(self).endswith(".jsonl"):
        reads.append(str(self))
    return _open(self, mode, *a, **k)


def spy_stat(self, *a, **k):
    stats.append(str(self))
    return _stat(self, *a, **k)


Path.open, Path.stat = spy_open, spy_stat


def enc(cwd: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


def world(name, argv, decoys=0, pinned=None, named=None):
    """세계 1개: projects 폴더 + 가짜 ps·tmux + 좌석 1(pane pid 500 → 셸 501 → claude 502)."""
    w = ROOT / name
    proj = w / "projects" / enc(CWD_A)
    proj.mkdir(parents=True)
    fake = w / "fake"
    fake.mkdir()
    for n, body in (("tmux", TMUX), ("ps", PS)):
        p = fake / n
        p.write_text(body, encoding="utf-8")
        p.chmod(0o755)
    (w / "panes").write_text("seat-a\t" + CWD_A + "\n", encoding="utf-8")
    (w / "pids").write_text("seat-a\t500\n", encoding="utf-8")
    (w / "psrows").write_text("501 500 /bin/zsh\n502 501 /Users/t/bin/claude " + argv + "\n", encoding="utf-8")
    now = time.time()
    for i in range(decoys):   # 미끼 = ② 길이 열렸을 때만 stat 된다
        p = proj / f"decoy-{i:04d}.jsonl"
        p.write_text('{"type":"user"}\n', encoding="utf-8")
        os.utime(p, (now - 7200, now - 7200))
    if pinned:
        p = proj / f"{pinned}.jsonl"
        p.write_text('{"type":"user"}\n', encoding="utf-8")
        os.utime(p, (now - 3600, now - 3600))
    if named:
        p = proj / "named.jsonl"
        p.write_text('{"type":"agent-name","agentName":"seat-a"}\n', encoding="utf-8")
        os.utime(p, (now, now))
    os.environ["PATH"] = str(fake) + os.pathsep + os.environ["PATH"]
    os.environ["PANE_FILE"], os.environ["PID_FILE"], os.environ["PS_FILE"] = str(w / "panes"), str(w / "pids"), str(w / "psrows")
    i_r, i_s = len(reads), len(stats)
    got = ut.find_jsonls(["seat-a"], "tmux", w / "projects", panes=[("seat-a", CWD_A)])
    decoy_stats = [s for s in stats[i_s:] if s.endswith(".jsonl") and Path(s).name.startswith("decoy-")]
    return got, reads[i_r:], decoy_stats, str(proj)


fail = 0


def chk(name, cond, detail=""):
    global fail
    if cond:
        print("PASS", name)
    else:
        fail += 1
        print("FAIL", name, str(detail)[:400])


def pinned_case(name, argv):
    """① 짚기 — U1.jsonl 로 바로 · 미끼 1000개 stat 0 · jsonl 열기 0."""
    got, r, ds, proj = world(name.replace(" ", "-"), argv, decoys=1000, pinned=U1)
    want = {("seat-a"): str(Path(proj) / f"{U1}.jsonl")}
    chk(name, got == want and ds == [] and r == [], (got, ds[:3], r[:3]))


pinned_case("J1", "--resume " + U1 + " --name S")
pinned_case("J2", "--resume=" + U1)
pinned_case("J2b", "-r " + U1)
pinned_case("J3", "--session-id " + U1)

got, r, _ds, proj = world("j4", "--resume " + U9, decoys=50, named=True)   # U9.jsonl 없음 = ② 그대로
chk("J4", got == {"seat-a": str(Path(proj) / "named.jsonl")} and r != [], (got, r[:3]))

got, r, _ds, proj = world("j5", "--resume", decoys=50, named=True)         # U 없음(대화 고르기 화면) = ② 그대로
chk("J5", got == {"seat-a": str(Path(proj) / "named.jsonl")} and r != [], (got, r[:3]))

print("FAIL", fail) if fail else print("ALL PASS")
sys.exit(1 if fail else 0)
EOPY

probe() { python3 "$T/probe.py" "$1" "$T/w-$2" 2>&1; }   # <bin 폴더> <세계 이름표>

sec "J1~J5 — 지금 bin"
out="$(probe "$BIN0" base)"; rc=$?
echo "$out"
[ "$rc" -eq 0 ] && ok "J1~J5 rc=0" || bad "J1~J5 rc=$rc"
[ "$(printf '%s\n' "$out" | grep -c '^PASS ')" -eq 6 ] && ok "PASS 6줄(J1·J2·J2b·J3·J4·J5)" || bad "PASS 줄 수 ≠ 6"

sec "bin=kit 같은 내용"
cmp -s "$BIN0/ft_api_outage_util.py" "$KIT/ft_api_outage_util.py" && ok "bin=kit ft_api_outage_util.py" || bad "bin≠kit ft_api_outage_util.py"

repl() {  # <파일> <옛 줄> <새 줄> — 사본 1곳만 바꾼다(변이)
  python3 - "$1" "$2" "$3" <<'EOPY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
assert sys.argv[2] in s, "변이 대상 없음: " + sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
EOPY
}

sec "변이 1 — 정규식을 --session-id 만으로 되돌림 → J1·J2 FAIL"
m1="$T/mut1"; cp -R "$BIN0" "$m1"
repl "$m1/ft_api_outage_util.py" '(?:--session-id|--resume|-r)' '--session-id' || bad "변이 1 사본 못 만듦"
if cmp -s "$BIN0/ft_api_outage_util.py" "$m1/ft_api_outage_util.py"; then bad "변이 1 사본 = 원본"
else out1="$(probe "$m1" mut1)"; rc1=$?
  echo "$out1" | grep -q '^FAIL J1' && ok "변이 1 → J1 FAIL" || bad "변이 1 을 J1 이 못 잡음"
  echo "$out1" | grep -q '^FAIL J2\b' && ok "변이 1 → J2 FAIL" || bad "변이 1 을 J2 가 못 잡음"
  echo "$out1" | grep -q '^PASS J3' && ok "변이 1 에서도 J3 PASS(지금 길 그대로)" || bad "변이 1 이 J3 를 깼다"
  [ "$rc1" -ne 0 ] && ok "변이 1 rc≠0" || bad "변이 1 rc=0"
fi

sec "변이 2 — U.jsonl 실재 확인(is_file) 빼기 → J4 FAIL"
m2="$T/mut2"; cp -R "$BIN0" "$m2"
repl "$m2/ft_api_outage_util.py" 'if cand.is_file():' 'if True:' || bad "변이 2 사본 못 만듦"
if cmp -s "$BIN0/ft_api_outage_util.py" "$m2/ft_api_outage_util.py"; then bad "변이 2 사본 = 원본"
else out2="$(probe "$m2" mut2)"; rc2=$?
  echo "$out2" | grep -q '^FAIL J4' && ok "변이 2 → J4 FAIL" || bad "변이 2 를 J4 가 못 잡음"
  [ "$rc2" -ne 0 ] && ok "변이 2 rc≠0" || bad "변이 2 rc=0"
fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
