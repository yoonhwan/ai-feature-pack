#!/usr/bin/env bash
# test_inbox_count_rotate_r1052.sh — r1052 단계 2: ft-inbox `show --count` · 술어 하나(B2) · `rotate` · show 머리 줄 · 상황판 소비자
#   S1 미닫힘 묶음(행 2 · 둘 다 before 전) → ROTATED 1 rows=2 · 보관 행 waived.rotated · show 에서 빠짐 · show 첫 줄 «회전 보관» (B3·B4)
#   S2 행 하나 전 · 하나 뒤 → KEPT(가장 새 행 기준) · S4 닫힌 묶음은 그대로 · S5 같은 날 2회 = 덧붙임
#   S3 사유에 «판정 N» 없음 → rc2 · 큐 바이트 그대로 · 보관 파일 없음
#   S6 --count «OPEN 3» · 본문 파일 open·exists 0회 · S7 회신 #N 으로 답한 묶음 → show·--count·--seqs 셋 다 제외(남의 계보 답은 무관)
#   S8 미닫힘 20,000 묶음 --count ≤ 2초 · S9 ft_board_env.inbox() 숫자 = --count 숫자(본문 못 읽는 픽스처)
#   변이 6종: --count 가 view 를 부름 · answered 빼기 · 가장 옛 행 기준 · 사유 검사 끔 · 머리 줄 끔 · 상황판 옛 호출 → 각각 FAIL 로 잡힌다
# 임시 FT_ROOT(mktemp) 만 · 실 큐·실 우편함 쓰기 0 · 고정 sleep 0 · 자기 재호출 0 · 시험 1개 70초 이하(timeout 70 · ulimit -u).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }
ms()  { python3 -c 'import time;print(int(time.time()*1000))'; }
T0="$(ms)"; st() { echo "⏱ $1 $(( $(ms) - T0 ))ms"; }
Q='master-x#1'
ib() { local r="$1"; shift; FT_ROOT="$r" python3 "${IB:-$BIN/ft-inbox.py}" "$@"; }

# ── 픽스처: mk <root> <종류> — 큐 master-x.jsonl (행: group·ts·mark) ──
cat > "$T/mk.py" <<'PY'
import json, os, sys
root, kind = sys.argv[1], sys.argv[2]
qdir = os.path.join(root, ".fable-team", "state", "inbox"); bdir = os.path.join(root, ".fable-team", "comm", "bodies")
os.makedirs(qdir, exist_ok=True); os.makedirs(bdir, exist_ok=True)
def row(seq, group, ts, closed=False, body=True):
    p = os.path.join(bdir, f"{seq}.txt")
    if body:
        open(p, "w", encoding="utf-8").write(f"[a#1->master-x#1] {seq} 첫 줄\n")
    m = {"kind": "처리", "note": "닫힘", "ts": ts} if closed else None
    return {"seq": seq, "ts": ts, "from": "a#1", "to": "master-x#1", "cls": "⑤" if closed else "③", "prio": 5.0 if closed else 3.0,
            "group": group, "body_path": p, "mark": m, "reported": closed, "via": "rule"}
OLD, NEW = "2026-10-01T00:00:00", "2026-10-30T00:00:00"
rows = []
if kind == "rot":      # gA 옛·열림 2행 · gB 옛·닫힘 · gC 새·열림 · gD 옛1+새1·열림
    rows = [row(1, "gA", OLD), row(2, "gA", OLD), row(3, "gB", OLD, True), row(4, "gC", NEW), row(5, "gD", OLD), row(6, "gD", NEW)]
elif kind == "closedold":   # 옛 닫힌 묶음만
    rows = [row(1, "gB", OLD, True)]
elif kind == "three":  # 미닫힘 3 · 본문 파일 있음·없음 섞임
    rows = [row(1, "g1", NEW), row(2, "g2", NEW, body=False), row(3, "g3", NEW), row(4, "g4", NEW, True)]
elif kind == "answered":    # 단일 행 묶음 2 — 시험이 «회신 #1» 쪽지를 따로 둔다
    rows = [row(1, "g1", NEW), row(2, "g2", NEW)]
elif kind == "big":
    rows = [row(i, f"g{i}", NEW, body=False) for i in range(1, 20001)]
with open(os.path.join(qdir, "master-x.jsonl"), "w", encoding="utf-8") as f:
    f.writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
PY
mk() { python3 "$T/mk.py" "$1" "$2"; }
shown() { python3 -c 'import sys,re;print(" ".join(sorted(set(re.findall(r"미닫힘=([0-9,]+)"," ".join(sys.stdin.read().split("\n")))))))'; }

# ── S1·S2·S4·S5 (rot) ──
R1="$T/r1"; mk "$R1" rot
Q1="$R1/.fable-team/state/inbox/master-x.jsonl"; ARC="$R1/.fable-team/state/inbox/archive/master-x-rotated-$(date +%Y%m%d).jsonl"
ib "$R1" show "$Q" > "$T/s1.before" 2>&1
OUT="$(ib "$R1" rotate "$Q" --before 2026-10-15T00:00:00 "판정 3000 시험")"; RC=$?
echo "$OUT" | head -3
ck "S1 rotate rc0" $RC
echo "$OUT" | grep -qE '^ROTATED 1 rows=2 KEPT 3 file=.*-rotated-[0-9]{8}\.jsonl$'; ck "S1 ROTATED 1 rows=2 KEPT 3 file=… (S2 gD · S4 gB 는 건드리지 않음)" $?
python3 - "$ARC" "$Q1" <<'PY'; ck "S1 보관 행 2개 · waived.rotated=true · seq 1,2 / 큐에 gA 없음 · gB·gC·gD 남음" $?
import json, sys
a = [json.loads(x) for x in open(sys.argv[1], encoding="utf-8")]
q = [json.loads(x) for x in open(sys.argv[2], encoding="utf-8")]
assert [x["seq"] for x in a] == [1, 2] and all(x["waived"]["rotated"] is True and "판정 3000" in x["waived"]["by"] and x["waived"]["ts"] for x in a), a
assert sorted({x["group"] for x in q}) == ["gB", "gC", "gD"] and len(q) == 4, q
PY
ib "$R1" show "$Q" > "$T/s1.after"
head -1 "$T/s1.after" | grep -qE '^회전 보관 1묶음 — .*-rotated-[0-9]{8}\.jsonl\(마지막 회전 [0-9T:-]+\)$'; ck "S1 B4 show 첫 줄 «회전 보관 1묶음 — <파일>(마지막 회전 <ts>)»" $?
grep -q "g gA\|] gA " "$T/s1.after" && bad "S1 show 에 gA 가 남음" || ok "S1 show 에서 gA 빠짐"
[ "$(wc -l < "$R1/.fable-team/state/inbox/rotated.log" | tr -d ' ')" = 1 ] && grep -q "groups=1 rows=2" "$R1/.fable-team/state/inbox/rotated.log"; ck "S1 B4 rotated.log 1줄/회 (groups=1 rows=2)" $?
ib "$R1" show "$Q" --seqs | head -1 | grep -q '^회전 보관' && bad "S1 --seqs 에 머리 줄이 섞임(SHOW_LINE 깨짐)" || ok "S1 --seqs 는 머리 줄 없음"
# S5 같은 날 2회 — 보관 파일 덧붙임(앞 2줄 보존)
ib "$R1" rotate "$Q" --before 2026-11-30T00:00:00 "판정 3000 시험2" | grep -qE '^ROTATED 2 rows=3 KEPT 1 '; ck "S5 두 번째 rotate = gC·gD 3행 · KEPT 1(gB 닫힘)" $?
python3 - "$ARC" <<'PY'; ck "S5 같은 날 2회 = 보관 파일 5줄 · 앞 2줄(seq 1,2) 보존" $?
import json, sys
a = [json.loads(x)["seq"] for x in open(sys.argv[1], encoding="utf-8")]
assert a[:2] == [1, 2] and len(a) == 5, a
PY
# S4 닫힌 묶음만
R4="$T/r4"; mk "$R4" closedold
ib "$R4" rotate "$Q" --before 2026-12-01T00:00:00 "판정 3000 시험" | grep -qE '^ROTATED 0 rows=0 KEPT 1 file=-$'; ck "S4 닫힌 묶음(before 전) = ROTATED 0 · 큐 그대로" $?
[ ! -e "$R4/.fable-team/state/inbox/rotated.log" ]; ck "S4 회전 0 이면 rotated.log 줄 없음" $?
st "S1·S2·S4·S5"

# ── S3 사유 검사 ──
R3="$T/r3"; mk "$R3" rot; cp "$R3/.fable-team/state/inbox/master-x.jsonl" "$T/s3.q"
ib "$R3" rotate "$Q" --before 2026-10-15T00:00:00 "그냥 정리" >/dev/null 2>"$T/s3.err"; RC3=$?
[ "$RC3" = 2 ]; ck "S3 사유에 «판정 N» 없음 → rc2 (rc=$RC3)" $?
cmp -s "$T/s3.q" "$R3/.fable-team/state/inbox/master-x.jsonl" && [ ! -d "$R3/.fable-team/state/inbox/archive" ]; ck "S3 큐 바이트 그대로 · 보관 파일 없음" $?
st "S3"

# ── S6 --count + 본문 접근 0 ──
cat > "$T/audit.py" <<'PY'
import builtins, os, runpy, sys
seen = []
_o, _s = builtins.open, os.stat
def op(f, *a, **k):
    if "bodies" in str(f): seen.append(("open", str(f)))
    return _o(f, *a, **k)
def st(p, *a, **k):
    if "bodies" in str(p): seen.append(("stat", str(p)))
    return _s(p, *a, **k)
builtins.open, os.stat = op, st
bin_dir, argv = sys.argv[1], sys.argv[2:]
sys.argv = ["ft-inbox.py"] + argv
sys.path.insert(0, bin_dir)
try:
    runpy.run_path(os.path.join(bin_dir, "ft-inbox.py"), run_name="__main__")
except SystemExit:
    pass
print(f"BODY_ACCESS {len(seen)}", file=sys.stderr)
PY
R6="$T/r6"; mk "$R6" three
FT_ROOT="$R6" python3 "$T/audit.py" "$BIN" show "$Q" --count > "$T/s6.out" 2> "$T/s6.err"
head -1 "$T/s6.out" | grep -qx 'OPEN 3'; ck "S6 --count = «OPEN 3» (미닫힘 묶음 3 · 닫힌 1 제외)" $?
grep -qx 'OLDEST seq=1' "$T/s6.out"; ck "S6 상황판용 OLDEST seq=1 (가장 오래된 미닫힘)" $?
grep -qx 'BODY_ACCESS 0' "$T/s6.err"; ck "S6 본문 경로 open·stat 0회 ($(tr -d '\n' < "$T/s6.err"))" $?
FT_ROOT="$R6" python3 "$T/audit.py" "$BIN" show "$Q" 2>&1 >/dev/null | grep -qx 'BODY_ACCESS 0' && bad "S6 대조: 옛 show 는 본문을 건드려야 하는데 0회(감사 훅 무효)" || ok "S6 대조: 옛 show 는 본문 접근 >0 (감사 훅 유효)"
st "S6"

# ── S7 회신 #N = 셋 다 제외 ──
R7="$T/r7"; mk "$R7" answered
python3 - "$R7" <<'PY'
import json, os, sys
root = sys.argv[1]; os.makedirs(f"{root}/.fable-team/comm", exist_ok=True)
rows = [{"seq": 9000, "ts": "2026-10-30T01:00:00", "from": "master-x#1", "to": "a#1", "body": "회신 #1 — 처리함"},
        {"seq": 9001, "ts": "2026-10-30T01:00:01", "from": "other#1", "to": "a#1", "body": "회신 #2 — 남의 계보"}]
open(f"{root}/.fable-team/comm/mailbox.jsonl", "w", encoding="utf-8").write("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in rows))
PY
ib "$R7" show "$Q" > "$T/s7.show"; ib "$R7" show "$Q" --seqs > "$T/s7.seqs"; ib "$R7" show "$Q" --count > "$T/s7.count"
[ "$(shown < "$T/s7.show")" = 2 ] && [ "$(shown < "$T/s7.seqs")" = 2 ] && head -1 "$T/s7.count" | grep -qx 'OPEN 1'; ck "S7 show·--seqs·--count 모두 seq1(내 계보 회신) 제외 · seq2(남의 계보 회신) 유지" $?
st "S7"

# ── S8 20,000 묶음 --count ──
R8="$T/r8"; mk "$R8" big
a="$(ms)"; ib "$R8" show "$Q" --count > "$T/s8.out"; b="$(ms)"
head -1 "$T/s8.out" | grep -qx 'OPEN 20000'; ck "S8 OPEN 20000" $?
[ $((b - a)) -le 2000 ] && ok "S8 --count 20,000 묶음 ≤ 2초 ($((b - a))ms)" || bad "S8 --count 20,000 묶음 $((b - a))ms > 2000ms"
st "S8"

# ── S9 상황판 소비자: ft_board_env.inbox() 숫자 = --count 숫자 · 본문을 못 읽는 픽스처(chmod 000) ──
R9="$T/r9"; mk "$R9" three; chmod 000 "$R9"/.fable-team/comm/bodies/*.txt
cat > "$T/s9.py" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ft_board_env as e
r = e.inbox(Path(sys.argv[2]), "master-x#1")
print(r["unreported"], r["oldest_ts"])
sys.exit(0 if r["unreported"] == 3 else 1)
PY
env -u FT_BOARD_INBOX python3 "$T/s9.py" "$BIN" "$R9" > "$T/s9.out" 2>&1; ck "S9 inbox() = 3 (= --count 숫자) · 본문 못 읽어도 성공 ($(tr -d '\n' < "$T/s9.out" | cut -c1-60))" $?
st "S9"

# ── 변이 6종 ──
mkdir -p "$T/mini"; cp "$BIN/ft-inbox.py" "$BIN/ft_inbox_core.py" "$BIN/ft_inbox_window.py" "$BIN/ft_inbox_rotate.py" "$BIN/ft_board_env.py" "$T/mini/"
cat > "$T/mut.py" <<'PY'
import shutil, sys
src, dst, rel, old, new = sys.argv[1:6]
shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
p = f"{dst}/{rel}"; s = open(p, encoding="utf-8").read()
if old not in s: sys.exit(f"변이 대상 없음: {old!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
mut() { python3 "$T/mut.py" "$@" && ck "변이 적용 $4" 0 || bad "변이 적용 실패 $4"; }
# M1 B1: --count 가 view() 를 부름 → S6 본문 접근 >0
mut "$T/mini" "$T/m1" ft-inbox.py '        return cmd_count(seat)' '        return print("OPEN", len(view(read_q(qpath(seat)))))'
FT_ROOT="$R6" python3 "$T/audit.py" "$T/m1" show "$Q" --count 2>&1 >/dev/null | grep -qx 'BODY_ACCESS 0' && bad "M1 못 잡음(--count 가 view 를 불러도 S6 통과)" || ok "M1 --count 가 view 를 부름 → S6 잡힘"
# M2 B2: answered 빼기 → S7 count 어긋남
mut "$T/mini" "$T/m2" ft_inbox_rotate.py '    ans = answered_seqs(seat)
    og = open_groups' '    ans = frozenset()
    og = open_groups'
IB="$T/m2/ft-inbox.py" ib "$R7" show "$Q" --count | head -1 | grep -qx 'OPEN 1' && bad "M2 못 잡음(answered 빼도 S7 통과)" || ok "M2 answered 빼기 → S7 잡힘"
# M3 B3: 가장 새 행 대신 가장 옛 행 → S2(gD) 어긋남
mut "$T/mini" "$T/m3" ft_inbox_rotate.py 'max(datetime.fromisoformat' 'min(datetime.fromisoformat'
R3b="$T/r3b"; mk "$R3b" rot
IB="$T/m3/ft-inbox.py" ib "$R3b" rotate "$Q" --before 2026-10-15T00:00:00 "판정 3000 시험" | grep -qE '^ROTATED 1 rows=2 KEPT 3 ' && bad "M3 못 잡음(가장 옛 행 기준인데 S2 통과)" || ok "M3 가장 옛 행 기준 → S2 잡힘"
# M4 B3: 사유 검사 끔 → S3 rc2 아님
mut "$T/mini" "$T/m4" ft_inbox_rotate.py 'if not re.search(r"판정 [0-9]+", reason):' 'if False:'
R3c="$T/r3c"; mk "$R3c" rot
IB="$T/m4/ft-inbox.py" ib "$R3c" rotate "$Q" --before 2026-10-15T00:00:00 "그냥 정리" >/dev/null 2>&1; [ $? = 2 ] && bad "M4 못 잡음(사유 검사 꺼도 rc2)" || ok "M4 사유 검사 끔 → S3 잡힘"
# M5 B4: 머리 줄 끔 → S1 첫 줄 없음
mut "$T/mini" "$T/m5" ft_inbox_rotate.py '    if not os.path.exists(LOG):' '    if True:'
cp -R "$R1" "$T/r1m"
IB="$T/m5/ft-inbox.py" ib "$T/r1m" show "$Q" | head -1 | grep -q '^회전 보관' && bad "M5 못 잡음(머리 줄 껐는데 보임)" || ok "M5 머리 줄 끔 → S1 잡힘"
# M6 소비자: 상황판 옛 호출([master] 만) → 본문 못 읽는 픽스처에서 실패
mut "$T/mini" "$T/m6" ft_board_env.py '[master, "--count"]' '[master]'
env -u FT_BOARD_INBOX python3 "$T/s9.py" "$T/m6" "$R9" >/dev/null 2>&1 && bad "M6 못 잡음(상황판이 옛 호출인데 S9 통과)" || ok "M6 상황판 옛 호출 → S9 잡힘"
st "변이"
chmod 600 "$R9"/.fable-team/comm/bodies/*.txt
echo "fail=$fail"; [ "$fail" = 0 ]
