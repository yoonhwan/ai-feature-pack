#!/usr/bin/env bash
# test_inbox_show_seqs.sh — r1052: ft-inbox `show --seqs`(기계용 · 큐 끝 창) + mirror_board «글자 선거름» 큐 조회
#   ⓐ R1·R6  미닫힘 합집합 = show 와 같다 · show(옵션 없음) 출력 바이트 = 전판(골든)과 같다 · 잘린 창의 첫 묶음 = «보류(범위 밖)»
#   ⓑ R2·R3  본문 파일 open 0(지워도 같은 출력) · 줄마다 SHOW_LINE 통과 · 빈 큐·없는 큐 = EMPTY · 깨진 끝 줄 = stderr 1줄 + 나머지 유지
#   ⓒ R4     5,000 묶음 show --seqs ≤ 2초 · mirror 1패스 «인박스 확인» ≤ 7초(닫힘 판정도 함께 본다)
#   ⓓ R5     anywhere 선거름 — 다른 큐 창에 있으면 적재 0 · 어디에도 없으면 적재 1 · «인박스 밖» 셈
#   변이 4종(닫힘 판정 건너뜀 · 본문 읽기 되살림 · 무조건 매치 · 창 잘림 무시) → 각각 FAIL 로 잡힌다
# 임시 FT_ROOT(mktemp) 만 · 실 큐·실 우편함·실 슬랙 0 · 고정 sleep 0 · 자기 재호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="$ROOT/harness/bin"; FIX="$ROOT/harness/fixtures/r677"; KIT="$ROOT/harness/kit/slack-mirror"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }
ms()  { python3 -c 'import time;print(int(time.time()*1000))'; }
T0="$(ms)"; st() { echo "⏱ $1 $(( $(ms) - T0 ))ms"; }
le()  { [ "$2" -le "$3" ] && ok "$1 ($2 ≤ $3)" || bad "$1 ($2 > $3)"; }

# ── 픽스처 생성기: mk <FT_ROOT> <행수> [nobody|broken] [큐이름] [시작seq] ──
cat > "$T/mk.py" <<'PY'
import json, os, sys
root, n, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
qname = sys.argv[4] if len(sys.argv) > 4 else "master-x.jsonl"
seq0 = int(sys.argv[5]) if len(sys.argv) > 5 else 1000
qdir = os.path.join(root, ".fable-team", "state", "inbox")
bdir = os.path.join(root, ".fable-team", "comm", "bodies")
os.makedirs(qdir, exist_ok=True); os.makedirs(bdir, exist_ok=True)
rows = []
for i in range(n):
    seq = seq0 + i
    body = os.path.join(bdir, f"{seq}.txt")
    if mode != "nobody" and i % 97:
        with open(body, "w", encoding="utf-8") as f:
            f.write(f"[a#1->master-x#1] {seq} 첫 줄\n둘째 줄\n")
    mark = ({"kind": "처리", "note": "닫힘", "ts": "2026-10-22T00:00:00"} if i % 7 == 0
            else {"kind": "보류", "note": "확인", "ts": "2026-10-22T00:00:00"} if i % 11 == 0 else None)
    rows.append({"seq": seq, "ts": "2026-10-22T00:00:00", "from": f"a#{i % 5}", "to": "master-x#1",
                 "cls": "③" if i % 2 == 0 else "⑤", "prio": 3.0 if i % 2 == 0 else 5.0, "group": f"g-{seq}",
                 "body_path": body, "mark": mark, "reported": mark is not None, "via": "rule"})
with open(os.path.join(qdir, qname), "w", encoding="utf-8") as f:
    f.writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
if mode == "broken":  # 끝 줄이 잘린 json(append 중단) — ft-inbox 는 WARN 1줄 남기고 그 줄만 버린다
    with open(os.path.join(qdir, qname), "a", encoding="utf-8") as f:
        f.write('{"seq": 999999, "ts": "2026-10-22T00:00:00", "from": "a#1", "cls": "③", "pri')
PY
mk() { mkdir -p "$1"; python3 "$T/mk.py" "$1" "$2" "${3:-}" ${4:+"$4"} ${5:+"$5"} >/dev/null; }

# ── ⓐ R1·R6 ──
R1="$T/r1"; mk "$R1" 120
FT_ROOT="$R1" python3 "$FIX/ft-inbox-base.py" show 'master-x#1' > "$T/base.out" 2>"$T/base.err"; ck "ⓐ 전판(골든) show rc0" $?
FT_ROOT="$R1" python3 "$BIN/ft-inbox.py" show 'master-x#1' > "$T/show.out" 2>"$T/show.err"; ck "ⓐ show rc0" $?
cmp -s "$T/base.out" "$T/show.out"; ck "ⓐ R6 show(옵션 없음) 출력 바이트 = 전판과 같다(사람용 회귀 0)" $?
FT_ROOT="$R1" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs > "$T/seqs.out" 2>"$T/seqs.err"; ck "ⓐ show --seqs rc0" $?
python3 - "$T/show.out" "$T/seqs.out" <<'PY'
import re, sys
def unclosed(p):
    s = set()
    for ln in open(p, encoding="utf-8"):
        m = re.match(r"^\[[^\]]+\] \S+ seq=[0-9,]+ 미닫힘=(\d+(?:,\d+)*)? from=", ln)
        assert m, f"SHOW_LINE 불일치: {ln[:70]!r}"
        s |= {int(x) for x in (m.group(1) or "").split(",") if x}
    return s
a, b = unclosed(sys.argv[1]), unclosed(sys.argv[2])
print(f"  show={len(a)}건  show --seqs={len(b)}건")
sys.exit(0 if a == b and a else 1)
PY
ck "ⓐ R1 같은 큐의 미닫힘 합집합 동일(show = show --seqs)" $?

st "ⓐ"
# ── ⓑ R2·R3 ──
mv "$R1/.fable-team/comm/bodies" "$T/bodies-away"
FT_ROOT="$R1" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs > "$T/seqs-nobody.out" 2>"$T/seqs-nobody.err"; ck "ⓑ 본문 파일 없는 픽스처에서 show --seqs rc0" $?
cmp -s "$T/seqs.out" "$T/seqs-nobody.out"; ck "ⓑ R2 본문 파일 open 0 (지워도 출력 같다)" $?
python3 - "$T/seqs.out" "$KIT" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
import mirror_board as mb
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
bad = [ln for ln in lines if not mb.SHOW_LINE.match(ln)]
preview = [ln for ln in lines if "원문= | " not in ln or ln.split("원문= | ", 1)[1].strip()]
print(f"  줄 {len(lines)}개 · SHOW_LINE 불일치 {len(bad)}개 · 원문 자리 안 빈 줄 {len(preview)}개")
sys.exit(0 if lines and not bad and not preview else 1)
PY
ck "ⓑ R3 줄마다 SHOW_LINE 통과 · «원문= |» 자리 비움" $?
mkdir -p "$T/empty/.fable-team/state/inbox"
e1="$(FT_ROOT="$T/empty" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs 2>&1)"
[ "$e1" = "EMPTY" ] && ok "ⓑ 0줄 큐 = EMPTY" || bad "ⓑ 0줄 큐 출력: $e1"
e2="$(FT_ROOT="$T/empty" python3 "$BIN/ft-inbox.py" show 'nobody#1' --seqs 2>&1)"
[ "$e2" = "EMPTY" ] && ok "ⓑ 큐 파일 없음 = EMPTY" || bad "ⓑ 큐 파일 없음 출력: $e2"
R3="$T/r3"; mk "$R3" 40 broken
FT_ROOT="$R3" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs > "$T/broken.out" 2>"$T/broken.err"; ck "ⓑ 깨진 끝 줄이 있어도 rc0" $?
grep -q "WARN r1052 깨진 큐 줄 건너뜀" "$T/broken.err"; ck "ⓑ 깨진 줄 = stderr WARN 1줄(조용한 0 아님)" $?
[ -s "$T/broken.out" ] && ! grep -q 999999 "$T/broken.out" && ok "ⓑ 깨진 줄만 빠지고 나머지 줄은 그대로" || bad "ⓑ 깨진 줄 처리 어긋남"

st "ⓑ"
# ── ⓐ(보류 표시) 창 위가 잘린 경우 ──
RB="$T/rbig"; mk "$RB" 5000
FT_ROOT="$RB" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs > "$T/big.out" 2>"$T/big.err"; ck "ⓐ 창 잘림 픽스처 show --seqs rc0" $?
n="$(grep -c "보류(범위 밖)" "$T/big.out")"
[ "$n" = 1 ] && ok "ⓐ 창 위가 잘린 첫 묶음 = «보류(범위 밖)» 표시 1개" || bad "ⓐ 보류 표시 $n개(1이어야 함)"
grep -qE '^\[[^]]+\] g-[0-9]+ seq=[0-9,]+ 미닫힘=[0-9,]+ from=.*보류\(범위 밖\)$' "$T/big.out" && ok "ⓐ 보류 줄도 SHOW_LINE 통과" || bad "ⓐ 보류 줄 형식 어긋남"

# ── ⓒ R4 시간 ──
t0="$(ms)"; FT_ROOT="$RB" python3 "$BIN/ft-inbox.py" show 'master-x#1' --seqs >/dev/null 2>&1; t1="$(ms)"
le "ⓒ R4 5,000 묶음 show --seqs 경과(ms)" "$((t1 - t0))" 2000
python3 - "$KIT" "$RB" "$BIN/ft-inbox.py" "$T" <<'PY'
import json, sys, time
from pathlib import Path
kit, root, inbox, tmp = sys.argv[1:5]
sys.path.insert(0, kit)
import mirror_board as mb
asked = int(time.time())
open_seqs = list(range(3000, 3900, 3))  # 창 안(파일 끝 1MB)에 있는 열린 질문 300건
st = tmp and Path(tmp) / "board" / "state.json"
st.parent.mkdir(parents=True, exist_ok=True)
st.write_text(json.dumps({"open": {str(s): {"state": "open", "asked_at": asked, "key": f"q{s}", "what": "질문"} for s in open_seqs}}), encoding="utf-8")
t0 = time.time(); note = mb.close_from_inbox(st, inbox, "master-x#1", Path(root)); el = int((time.time() - t0) * 1000)
closed = {int(k) for k in json.loads(st.read_text(encoding="utf-8"))["resolved"]}
want = {s for s in open_seqs if (s - 1000) % 7 == 0 or (s - 1000) % 11 == 0}  # 닫힌 묶음 = mark 있고 보고된 줄
print(f"  mirror 1패스 {el}ms · 닫힘 {len(closed)}건 · note={note!r}")
sys.exit(0 if el <= 7000 and closed == want else 1)
PY
ck "ⓒ R4 mirror 1패스 «인박스 확인» ≤ 7초 · 닫힘 판정도 show 와 같다" $?

st "ⓐ보류·ⓒ"
# ── ⓓ R5 anywhere 선거름 ──
R5="$T/r5"; mk "$R5" 10 "" master-x.jsonl 1000; mk "$R5" 10 "" other.jsonl 2000
export STUB_LOG="$T/stub.log" REAL_INBOX="$BIN/ft-inbox.py"
cat > "$T/inbox-stub.sh" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in show) shift; exec python3 "$REAL_INBOX" show "$@" ;; *) exit 0 ;; esac
EOF
chmod +x "$T/inbox-stub.sh"
python3 - "$KIT" "$R5" "$T/inbox-stub.sh" "$T" <<'PY'
import json, sys, time
from pathlib import Path
kit, root, stub, tmp = sys.argv[1:5]
sys.path.insert(0, kit)
import mirror_board as mb
asked = int(time.time())
open_seqs = [1000, 2000, 3000]  # 1000 = planner 큐 · 2000 = 다른 큐 · 3000 = 어디에도 없음
st = Path(tmp) / "board5" / "state.json"; st.parent.mkdir(parents=True, exist_ok=True)
st.write_text(json.dumps({"open": {str(s): {"state": "open", "asked_at": asked, "key": f"q{s}", "what": "질문"} for s in open_seqs}}), encoding="utf-8")
note = mb.close_from_inbox(st, stub, "master-x#1", Path(root))
log = Path(tmp, "stub.log").read_text(encoding="utf-8")
print(f"  note={note!r} · 호출={log.strip().splitlines()}")
ok = ("ingest 3000" in log and "ingest 1000" not in log and "ingest 2000" not in log
      and "show master-x#1 --seqs" in log and note == "인박스 밖 2건")
sys.exit(0 if ok else 1)
PY
ck "ⓓ R5 다른 큐에 있으면 적재 0 · 어디에도 없으면 적재 1 · 인박스 밖 2건" $?

st "ⓓ"
# ── 변이 4종 (각각 FAIL 로 잡혀야 한다) ──
mkdir -p "$T/mini"; cp "$BIN/ft-inbox.py" "$BIN/ft_inbox_core.py" "$BIN/ft_inbox_window.py" "$T/mini/"
cat > "$T/mut.py" <<'PY'
import shutil, sys
src, dst, rel, old, new = sys.argv[1:6]
shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
p = f"{dst}/{rel}"
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit(f"변이 대상 없음: {old!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
mut() { python3 "$T/mut.py" "$@" && ck "변이 적용 $4" 0 || bad "변이 적용 실패 $4"; }

# M1 닫힘 판정 건너뜀 → ⓐ 미닫힘 합집합 어긋남
mut "$T/mini" "$T/m1" ft_inbox_window.py 'if not obligation_closed(x)' 'if False'
FT_ROOT="$R1" python3 "$T/m1/ft-inbox.py" show 'master-x#1' --seqs > "$T/m1.out" 2>&1
cmp -s "$T/seqs.out" "$T/m1.out" && bad "M1 변이를 못 잡음(닫힘 판정 건너뛰어도 같음)" || ok "M1 닫힘 판정 건너뜀 → 잡힘"
# M2 본문 읽기 되살림 → 본문 파일이 없어 rc≠0
mut "$T/mini" "$T/m2" ft_inbox_window.py '        if un:' '        if un:
            open(ms[0]["body_path"], encoding="utf-8").readline()'
FT_ROOT="$R1" python3 "$T/m2/ft-inbox.py" show 'master-x#1' --seqs >/dev/null 2>&1
[ $? = 0 ] && bad "M2 변이를 못 잡음(본문 open 0 위반인데 rc0)" || ok "M2 본문 읽기 되살림 → 잡힘"
# M3 무조건 매치(선거름 없음) → ⓓ 적재 0 이 됨
mut "$KIT" "$T/m3" mirror_board.py 'return found & want if want else found' 'return found | (want or set())'
python3 - "$T/m3" "$R5" "$T/inbox-stub.sh" "$T" <<'PY'
import json, sys, time
from pathlib import Path
kit, root, stub, tmp = sys.argv[1:5]
sys.path.insert(0, kit)
import mirror_board as mb
asked = int(time.time())
st = Path(tmp) / "board5m" / "state.json"; st.parent.mkdir(parents=True, exist_ok=True)
st.write_text(json.dumps({"open": {str(s): {"state": "open", "asked_at": asked, "key": "q", "what": "질문"} for s in [1000, 2000, 3000]}}), encoding="utf-8")
log = Path(tmp, "stub.log"); log.write_text("", encoding="utf-8")
mb.close_from_inbox(st, stub, "master-x#1", Path(root))
sys.exit(0 if "ingest 3000" in log.read_text(encoding="utf-8") else 1)
PY
[ $? = 0 ] && bad "M3 변이를 못 잡음(무조건 매치인데 적재함)" || ok "M3 무조건 매치 → 잡힘"
# M4 창 잘림 무시 → «보류(범위 밖)» 표시 사라짐
mut "$T/mini" "$T/m4" ft_inbox_window.py 'head = rows[0]["group"] if rows and cut else None' 'head = None'
FT_ROOT="$RB" python3 "$T/m4/ft-inbox.py" show 'master-x#1' --seqs > "$T/m4.out" 2>&1
grep -q "보류(범위 밖)" "$T/m4.out" && bad "M4 변이를 못 잡음(창 잘림 무시인데 보류 표시 있음)" || ok "M4 창 잘림 무시 → 잡힘"

st "변이"
echo "fail=$fail"; [ "$fail" = 0 ]
