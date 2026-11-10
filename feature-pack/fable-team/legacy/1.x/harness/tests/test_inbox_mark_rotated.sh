#!/usr/bin/env bash
# test_inbox_mark_rotated.sh — r430: `ft-inbox.sh mark <seq>` 가 «대상 못 찾음» 을 내던 구멍 — send 때 큐 적재가 빠진 쪽지
#  (실측 10-19: planner 큐에 110726·110770·110796 없음 · 쪽지 원본은 mailbox.log.jsonl) → mark 가 우편함 파일
#  mailbox.jsonl → mailbox.log.jsonl → mailbox.log.jsonl.N(숫자 순)에서 첫 1건을 찾아 이 좌석 계보 앞이면 적재 뒤 표시.
#  ⓐ mailbox.jsonl 에만 → MARKED file=mailbox.jsonl · 표식 = 좌석 큐 행 mark(기존 저장 위치 그대로)
#  ⓑ mailbox.log.jsonl 에만 → MARKED file=mailbox.log.jsonl
#  ⓒ mailbox.log.jsonl.N 에만 → MARKED file=…jsonl.2 (.2 와 .10 둘 다 있으면 숫자 순 = .2)
#  ⓓ 어디에도 없음 → rc1 · «대상 못 찾음 seq=<n> (N 파일 조회)» · 큐 불변(조용한 통과 0)
#  ⓔ 5MB 회전본 끝 행 조회 ≤1초
#  ⓕ 바뀐 두 파일에 600/300 0 · ⓖ 남의 계보 앞 쪽지 → rc1 · 내 큐에 적재 0
# 임시 FT_ROOT — 실 mailbox·실 인박스 쓰기 0 · Haiku 호출 0(분류 규칙표 ⑥ «참고» 본문 · FT_INBOX_HAIKU=false) · GIT_* 는 걸지 않는다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset FT_SEAT TMUX_PANE; export FT_INBOX_HAIKU=false
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

export FT_ROOT="$T/root"; COMM="$FT_ROOT/.fable-team/comm"; Q="$FT_ROOT/.fable-team/state/inbox"
mkdir -p "$COMM" "$Q"
ME="byz-x-master-claude"; SEAT="$ME#4"; INBOX=(python3 "$KIT/ft-inbox.py")
mail() {  # <파일> <seq> [to] — 우편함 행 1줄 append(ft-mbox.py 와 같은 json.dumps 꼴)
  python3 - "$COMM/$1" "$2" "${3:-$ME#3}" <<'PY'
import json, sys
with open(sys.argv[1], "a", encoding="utf-8") as f:
    f.write(json.dumps({"seq": int(sys.argv[2]), "ts": "2026-10-19T09:00:00", "to": sys.argv[3], "from": "y#1",
                        "body": f"[y#1->x#3] 참고 본문 {sys.argv[2]}"}, ensure_ascii=False) + "\n")
PY
}
qmark() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print((x["mark"] or {}).get("kind"))' "$Q/$ME.jsonl" "$1" 2>/dev/null; }

mail mailbox.jsonl 1001; mail mailbox.log.jsonl 1002; mail mailbox.log.jsonl.10 1003; mail mailbox.log.jsonl.2 1003
mail mailbox.log.jsonl.10 1004; mail mailbox.log.jsonl 1005 "byz-other-master-claude#1"

# ⓐ
OUT="$("${INBOX[@]}" mark 1001 처리 "a" --seat "$SEAT" 2>&1)"; rc=$?
eq "ⓐ rc" "$rc" "0"; echo "$OUT" | grep -qx "MARKED seq=1001 file=mailbox.jsonl" && ok "ⓐ MARKED file=mailbox.jsonl" || bad "ⓐ 출력 ($OUT)"
eq "ⓐ 표식 = 좌석 큐 행 mark" "$(qmark 1001)" "처리"
# ⓑ
OUT="$("${INBOX[@]}" mark 1002 보류 "b" --seat "$SEAT" 2>&1)"; rc=$?
eq "ⓑ rc" "$rc" "0"; echo "$OUT" | grep -qx "MARKED seq=1002 file=mailbox.log.jsonl" && ok "ⓑ MARKED file=mailbox.log.jsonl" || bad "ⓑ 출력 ($OUT)"
eq "ⓑ 큐 행 mark" "$(qmark 1002)" "보류"
# ⓒ
OUT="$("${INBOX[@]}" mark 1003 처리 "c" --seat "$SEAT" 2>&1)"; rc=$?
eq "ⓒ rc" "$rc" "0"; echo "$OUT" | grep -qx "MARKED seq=1003 file=mailbox.log.jsonl.2" && ok "ⓒ 숫자 순 .2 (.10 보다 먼저)" || bad "ⓒ 출력 ($OUT)"
OUT="$("${INBOX[@]}" mark 1004 처리 "c2" --seat "$SEAT" 2>&1)"; rc=$?
eq "ⓒ' .10 에만 rc" "$rc" "0"; echo "$OUT" | grep -qx "MARKED seq=1004 file=mailbox.log.jsonl.10" && ok "ⓒ' MARKED file=mailbox.log.jsonl.10" || bad "ⓒ' 출력 ($OUT)"
# 이미 큐에 있는 seq 재표시 = 적재 0(INGEST 줄 0) · MARKED 그대로
OUT="$("${INBOX[@]}" mark 1001 위임 "again" --seat "$SEAT" 2>&1)"
echo "$OUT" | grep -q '^INGEST' && bad "재표시에 INGEST ($OUT)" || ok "재표시 = 적재 0"
eq "재표시 큐 행 수" "$(wc -l < "$Q/$ME.jsonl" | tr -d ' ')" "4"
# ⓓ
Q0="$(md5 -q "$Q/$ME.jsonl")"
ERR="$("${INBOX[@]}" mark 999999 처리 "d" --seat "$SEAT" 2>&1 >/dev/null)"; rc=$?
eq "ⓓ rc" "$rc" "1"
echo "$ERR" | grep -q "대상 못 찾음 seq=999999 (4 파일 조회)" && ok "ⓓ «대상 못 찾음 seq= (N 파일 조회)»" || bad "ⓓ 메시지 ($ERR)"
eq "ⓓ 큐 불변" "$(md5 -q "$Q/$ME.jsonl")" "$Q0"
# ⓖ 남의 계보 앞 쪽지
ERR="$("${INBOX[@]}" mark 1005 처리 "g" --seat "$SEAT" 2>&1 >/dev/null)"; rc=$?
eq "ⓖ 남의 쪽지 rc" "$rc" "1"; eq "ⓖ 내 큐 불변" "$(md5 -q "$Q/$ME.jsonl")" "$Q0"
[ -e "$Q/byz-other-master-claude.jsonl" ] && bad "ⓖ 남의 큐 생성" || ok "ⓖ 남의 큐 쓰기 0"
# ⓔ 5MB 회전본 끝 행
python3 - "$COMM/mailbox.log.jsonl.3" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    pad = "가" * 1200
    for i in range(1400):
        f.write(json.dumps({"seq": 500000 + i, "ts": "2026-10-19T09:00:00", "to": "z#1", "from": "y#1", "body": pad}, ensure_ascii=False) + "\n")
PY
mail mailbox.log.jsonl.3 2001
eq "ⓔ 회전본 ≥5MB" "$([ "$(wc -c < "$COMM/mailbox.log.jsonl.3")" -ge 5000000 ] && echo y)" "y"
S=$(python3 -c 'import time;print(time.time())')
OUT="$("${INBOX[@]}" mark 2001 처리 "e" --seat "$SEAT" 2>&1)"; rc=$?
E=$(python3 -c "import time;print(round(time.time()-$S,2))")
eq "ⓔ rc" "$rc" "0"; echo "$OUT" | grep -qx "MARKED seq=2001 file=mailbox.log.jsonl.3" && ok "ⓔ MARKED file=mailbox.log.jsonl.3" || bad "ⓔ 출력 ($OUT)"
python3 -c "import sys;sys.exit(0 if $E <= 1.0 else 1)" && ok "ⓔ 조회 ${E}s ≤ 1s" || bad "ⓔ 조회 ${E}s > 1s"
# ⓕ
n=$(grep -cE '\b(600|300)\b' "$KIT/ft-inbox.py" "$KIT/ft_inbox_core.py" | awk -F: '{s+=$2} END{print s+0}')
eq "ⓕ 600/300 0" "$n" "0"

echo "FAILED=$fail"; [ "$fail" -eq 0 ]
