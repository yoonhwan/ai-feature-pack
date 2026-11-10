#!/usr/bin/env bash
# test_hil_register_reply_wait_r1587.sh — ft-hil 발급 자리에서 답글 감시 자동 등록(ⓐ~ⓒ) + 변이 M1
#   ⓐ approve-merge <sha40> --oppa-slack <ts> 계획 발급 = 장부 open 1줄(ts·h번호·sha40) → 점검 1회(가짜 답글) → desk 쪽지 1통
#   ⓑ --oppa-slack 없는 계획 = 장부 0줄 · 같은 계획 재발급 = 장부 1줄 그대로(r1574 멱등)
#   ⓒ 등록 실패(장부 못 씀) = h 발급 rc 0 그대로 + stderr «감시 등록 실패 <ts>» 1줄(조용한 실패 0)
#   M1 = ft-hil.sh 의 --register-plan 호출 제거 → ⓐ «장부 1줄» FAIL(시험이 잡는다)
#   격리: 임시 FT_ROOT·HIL_DIR·장부 · 가짜 mbox(발신 기록) · 가짜 replies(실 Slack 0) · 판정기 5종 끔(WARN)
#   안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0 · exit 0 = 전부 통과
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO_LIMIT=70
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
HIL="$BIN/ft-hil.sh"
TOOL="$BIN/ft_desk_reply_wake.py"
[ -f "$HIL" ] || { echo "도구 없음: $HIL" >&2; exit 1; }
[ -f "$TOOL" ] || { echo "도구 없음: $TOOL" >&2; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
has() { if grep -Fq -- "$1" "$2" 2>/dev/null; then echo "  OK   $3"; else echo "  FAIL $3 — 없음[$1] in ${2##*/}"; fail=1; fi; }

QTS=1794310751.988869               # 질문 글 ts(실사건 그대로)
RTS=1794310798.099999               # 오빠 답글 ts
SHA=53603ed56b4061e68f6e9bc0d64a3676149c8ef5
DESK="byz-planner-desk-pi#127"
MASTER="byz-planner-master-pi#249"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"
SENT="$T/sent.tsv"; : > "$SENT"
printf '{"_master":"%s","_desk":"%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"

# 가짜 mbox(send = 받는이·본문 1줄 기록 · 실제 발신 0) · 가짜 replies(부모 글 + 오빠 답글 1개)
cat > "$T/mbox.sh" <<SH
#!/usr/bin/env bash
printf '%s\t%s\n' "\$2" "\$4" >> "$SENT"
echo "QUEUED seq=stub"
SH
cat > "$T/replies.sh" <<SH
#!/usr/bin/env bash
cat "$T/replies.json"
SH
python3 - "$T/replies.json" "$QTS" "$RTS" "$SHA" <<'PY'
import json, sys
out, qts, rts, sha = sys.argv[1:5]
msgs = [{"ts": qts, "user": "U0C9GRFHJ", "text": "sha %s 승인 요청" % sha}, {"ts": rts, "user": "U0AC2JF0M7D", "text": "승인"}]  # r1606: 답글 «내용» 판정 — 승인 낱말과 전체 일치
json.dump({"ok": True, "messages": msgs}, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
mkplan() {  # <이름> <approve-merge 인자들> — 계획 파일을 쓰고 경로를 PLAN 에 둔다(중첩 인용 회피)
  PLAN="$T/$1.sh"; shift
  printf '#!/usr/bin/env bash\nbash bin/ft-autonomy.sh approve-merge %s\n' "$*" > "$PLAN"
}
HILENV=(HIL_DIR="$T/hil" HIL_CLIP=0 FT_ROOT="$ROOT" FT_SECRET_JUDGE=/nope FT_TRAFFIC_JUDGE=/nope
        FT_SCOPE_JUDGE=/nope FT_MIX_JUDGE=/nope FT_PACK_PATH_JUDGE=/nope FT_DESK_REPLY_LEDGER="$LEDGER")
run_hil() { ( cd "$ROOT" && env "${HILENV[@]}" timeout $TO_LIMIT bash "$HIL" --add "$1" ); }   # stdout 1줄 · stderr = WARN/실패
scan() { ( cd "$ROOT" && env "${HILENV[@]}" FT_MBOX_SH="$T/mbox.sh" FT_SLACK_REPLIES_CMD="bash $T/replies.sh" \
           FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" timeout $TO_LIMIT python3 "$TOOL" ); }
lines() { if [ -f "$LEDGER" ]; then wc -l < "$LEDGER" | tr -d ' '; else echo 0; fi; }
field() { python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r.get(sys.argv[2],""))' "$LEDGER" "$1" 2>/dev/null; }

echo "== ⓐ approve-merge --oppa-slack 계획 발급 = 장부 open 1줄 → 점검 → desk 1통 =="
mkplan a-approve "$SHA --oppa-slack $QTS"
OUT_A="$(run_hil "$PLAN" 2>"$T/err-a")"; RC_A=$?
chk "ⓐ 발급 rc=0" 0 "$RC_A"
case "$OUT_A" in "! bash $T/hil/h"[0-9]*) echo "  OK   ⓐ stdout = «! bash <h>» 1줄";; *) echo "  FAIL ⓐ stdout: $OUT_A"; fail=1;; esac
HN_A="${OUT_A##*/h}"
chk "ⓐ 장부 1줄" 1 "$(lines)"
chk "ⓐ 장부 q_ts = 계획의 --oppa-slack 값" "$QTS" "$(field q_ts)"
chk "ⓐ 장부 h = 발급된 h 번호" "h$HN_A" "$(field h)"
chk "ⓐ 장부 sha = 계획의 approve-merge sha" "$SHA" "$(field sha)"
chk "ⓐ 장부 state" "open" "$(field state)"
: > "$SENT"
scan >/dev/null 2>"$T/err-scan"; RC_S=$?
chk "ⓐ 점검 rc=0" 0 "$RC_S"
chk "ⓐ desk 쪽지 1통" 1 "$(wc -l < "$SENT" | tr -d ' ')"
chk "ⓐ 받는이 = seats-planner.json _desk" "$DESK" "$(cut -f1 "$SENT")"
chk "ⓐ 본문 = «[오빠 답글] h<N> ts=<답글> → 실행 차례»" "[오빠 답글] h$HN_A ts=$RTS → 실행 차례" "$(cut -f2 "$SENT")"

echo "== ⓑ 대상 아님 0줄 · 같은 계획 재발급 = 1줄 그대로(멱등) =="
mkplan a-approve "$SHA --oppa-slack $QTS"; run_hil "$PLAN" >/dev/null 2>&1
chk "ⓑ 같은 계획 재발급 = 장부 1줄 그대로" 1 "$(lines)"
rm -f "$LEDGER"
mkplan b-noslack "$SHA"
OUT_B="$(run_hil "$PLAN" 2>"$T/err-b")"; RC_B=$?
chk "ⓑ --oppa-slack 없음 = h 발급 rc=0" 0 "$RC_B"
chk "ⓑ --oppa-slack 없음 = 장부 0줄(대상 아님)" 0 "$(lines)"
case "$OUT_B" in "! bash $T/hil/h"[0-9]*) echo "  OK   ⓑ h 발급은 그대로";; *) echo "  FAIL ⓑ h 발급: $OUT_B"; fail=1;; esac

echo "== ⓒ 등록 실패 = h 발급 rc 그대로 + stderr «감시 등록 실패 <ts>» 1줄 =="
mkplan c-ok "$SHA --oppa-slack $QTS"; run_hil "$PLAN" >/dev/null 2>&1
BEFORE="$(lines)"
chmod 555 "$ROOT/.fable-team/state"
mkplan c-bad 1111111111111111111111111111111111111111 --oppa-slack 1794310760.123456
OUT_C="$(run_hil "$PLAN" 2>"$T/err-c")"; RC_C=$?
chmod 755 "$ROOT/.fable-team/state"
chk "ⓒ h 발급 rc = 0 그대로(등록 실패가 발급을 막지 않는다)" 0 "$RC_C"
case "$OUT_C" in "! bash $T/hil/h"[0-9]*) echo "  OK   ⓒ h 발급 stdout 은 그대로";; *) echo "  FAIL ⓒ h 발급: $OUT_C"; fail=1;; esac
chk "ⓒ stderr = «감시 등록 실패 <ts>» 1줄" 1 "$(grep -c '감시 등록 실패 1794310760\.123456' "$T/err-c" || true)"
chk "ⓒ 실패한 등록은 장부를 안 늘린다" "$BEFORE" "$(lines)"

echo "== kit 사본 2개가 bin 과 같다(cmp0) =="
cmp -s "$HIL" "$BIN/../kit/fable-team/bin/ft-hil.sh" && echo "  OK   cmp0 ft-hil.sh" || { echo "  FAIL cmp0 ft-hil.sh"; fail=1; }
cmp -s "$TOOL" "$BIN/../kit/fable-team/bin/ft_desk_reply_wake.py" && echo "  OK   cmp0 ft_desk_reply_wake.py" || { echo "  FAIL cmp0 ft_desk_reply_wake.py"; fail=1; }

echo "== 변이 M1: ft-hil.sh 의 --register-plan 호출 제거 → ⓐ «장부 1줄» 이 잡는다 =="
MUT="$T/mut"; mkdir -p "$MUT"
python3 - "$HIL" "$MUT/ft-hil.sh" <<'PY'
import sys, re, pathlib
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
t = src.read_text(encoding="utf-8")
t2, n = re.subn(r' \[ -z "\$new" \] \|\| FT_ROOT=.*?ft_desk_reply_wake\.py" --register-plan "\$t" "h\$n" >/dev/null \|\| true', "", t, count=1)
assert n == 1, "--register-plan 호출 줄을 못 찾음"
dst.write_text(t2, encoding="utf-8")
PY
chmod 644 "$MUT/ft-hil.sh"; rm -f "$LEDGER"; mkplan m1 "$SHA --oppa-slack $QTS"
( cd "$ROOT" && env "${HILENV[@]}" timeout $TO_LIMIT bash "$MUT/ft-hil.sh" --add "$PLAN" >/dev/null 2>&1 )
if [ "$(lines)" = 1 ]; then echo "  FAIL M1 — 호출을 뺐는데도 장부 1줄(시험이 약하다)"; fail=1; else echo "  OK   M1 호출 제거 → ⓐ «장부 1줄» 검사 FAIL(시험이 잡는다 · 실제 $(lines)줄)"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (ⓐ~ⓒ · 변이 M1 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
