#!/usr/bin/env bash
# test_r1883_stall_team_no_master.sh — r1883 m = 팀장 손 없는 팀(_master 빈 값 ∨ _master tmux 세션 없음) ∧ 배정 가능 대기 카드(card_ready==ready) ≥ 1
#   → stall 셈 포함 · planner·harness master 에 팀마다 1통 · 같은 서명(팀·_master) 재알림 0.
#   반례 ①~⑥ + 변이 M1(카드 조건 빼기 → ⑤ FAIL) · M2(서명 기억 빼기 → ② FAIL) + kit 짝 cmp.
# 격리: 임시 루트 · 가짜 명부·tmux·mbox·카드(_stall_world · FT_TMUX) — 실 장부·명부·tmux·mbox 쓰기 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cat >"$T/drive.py" <<'PY'
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[3])
from _stall_world import World, counts
BIN, case = Path(sys.argv[1]), sys.argv[2]
def world(master="nb-master#1", live=False, cards=("W1", "W2")):
    w = World(Path(sys.argv[4]) / case)
    w.env.update(FT_CRITICAL_OFF="1", FT_STALL_PENALTY_AUTO="0")
    w.team("harness", "harness-master#1", [])
    w.team("nb", master or "nb-master#1", ["nb-nano#0"])
    roster(w, master)
    if not live:  # 팀장 세션 없음(tmux 목록에서 뺀다)
        w.live = [s for s in w.live if s != (master or "nb-master#1")]
        w._tmux()
    w.cards("nb", list(cards))
    return w
def roster(w, master):
    p = w.root / ".fable-team/seats-nb.json"
    d = json.loads(p.read_text()); d["_master"] = master
    p.write_text(json.dumps(d))
def scan(w):
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stdout + r.stderr
    return counts(next((x for x in r.stdout.splitlines() if x.startswith("stall=")), "") or "-")  # 첫 줄 앞 WARN(_master 빔) 건너뜀
def notes(w):  # [팀장 없음] 쪽지 → (받는이, 본문)
    return [(x.split("|")[1], x) for x in w.mbox_log() if x.startswith("send|") and "[팀장 없음]" in x]
def each1(ns, team="nb"):
    return sorted(to for to, _ in ns) == ["harness-master#1", "planner#1"] and all(f"[팀장 없음] {team} " in b for _, b in ns)
def chk(name, ok, extra=""):
    print(("ok " if ok else "NG ") + name + (f" — {extra}" if extra and not ok else ""))
    return ok
ok = True
if case == "seq":  # ①②⑥ 한 세계
    w = world()
    c = scan(w); ns = notes(w)
    ok &= chk("① m=1 · stall 포함 · planner·harness 각 1통", c.get("m") == "1" and int(c.get("stall", 0)) >= 1 and each1(ns)
              and all("대기 카드 2" in b and "_master nb-master#1" in b and "successor-open" in b for _, b in ns), f"{c} {ns}")
    w.advance(120)
    c = scan(w)
    ok &= chk("② 같은 서명 → 쪽지 0", c.get("m") == "1" and len(notes(w)) == 2, f"{c} {notes(w)[2:]}")
    roster(w, "nb-master#2"); w.advance(120)
    c = scan(w); new = notes(w)[2:]
    ok &= chk("⑥ 교대(Y 세션 없음) → 새 서명 각 1통", c.get("m") == "1" and each1(new) and all("_master nb-master#2" in b for _, b in new), f"{c} {new}")
elif case == "empty":
    w = world(master="", cards=("W1",))
    c = scan(w); ns = notes(w)
    ok &= chk("③ _master 빈 값 · 대기 1 → m=1 · 각 1통", c.get("m") == "1" and each1(ns) and all("대기 카드 1" in b and "_master 빈 값" in b for _, b in ns), f"{c} {ns}")
elif case == "live":
    w = world(live=True)
    c = scan(w)
    ok &= chk("④ 팀장 세션 있음 → m=0", c.get("m") == "0" and not notes(w), f"{c} {notes(w)}")
elif case == "nocards":
    w = world(cards=())
    c = scan(w)
    ok &= chk("⑤ 대기 카드 0 → m=0", c.get("m") == "0" and not notes(w), f"{c} {notes(w)}")
sys.exit(0 if ok else 1)
PY
drive() { python3 "$T/drive.py" "$1" "$2" "$HERE/scripts" "$T/w-$3" >"$T/$3.log" 2>&1; }
for c in seq empty live nocards; do
  s=$SECONDS; drive "$KIT" "$c" "k-$c"; r=$?; sed 's/^/  /' "$T/k-$c.log"; ck "$c ($((SECONDS - s))초)" $r
done

# 변이 — 사본 bin 한 곳씩 바꾸면 그 반례가 FAIL 해야 한다
mutate() {  # $1 이름 $2 원문 $3 바꿀 글 $4 case
  rm -rf "$T/mb"; cp -Rp "$KIT" "$T/mb"
  python3 - "$T/mb/ft_stall_scan.py" "$2" "$3" <<'PY' || { echo "FAIL $1 — 변이 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  drive "$T/mb" "$4" "m-$4-$RANDOM"; [ $? -ne 0 ]; ck "$1 → $4 FAIL" $?
}
mutate "M1 대기 카드 조건 빼기" 'if m_names:' 'if True:' nocards
mutate "M2 서명 기억 빼기" 'if f["sig"] in sigs:' 'if False:' seq

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일
cmp -s "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" && [ "$(stat -f %Lp "$TRK/ft_stall_scan.py")" = "$(stat -f %Lp "$KIT/ft_stall_scan.py")" ]; ck "짝 사본 ft_stall_scan.py" $?
echo "FAIL=$fail"; [ "$fail" = 0 ]
