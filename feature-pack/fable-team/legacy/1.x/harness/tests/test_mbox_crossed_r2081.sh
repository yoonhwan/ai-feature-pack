#!/usr/bin/env bash
# test_mbox_crossed_r2081.sh — r2081 C: 받는 좌석이 내게 보낸 안 읽은 쪽지가 있는 채로 send = 보낸 쪽 stderr 1줄 + 받는 쪽 recv 1줄(막지 않는다).
#   ⑧ B→A 1통(안 읽음) 뒤 A→B = A stderr «엇갈림 B …1통(가장 새 #n HH:MM:SS)» · rc 0 · QUEUED 그대로 · 큐·기록 행 crossed 칸
#      → B recv = READ 줄 바로 아래 «엇갈림 — A 이 네 쪽지 #n(1통)를 안 읽고 보낸 글» / 안 읽은 7통 = 번호 5개 + (7통)
#   ⑨ 0통 = stdout QUEUED 1줄 · stderr = 기준판(desk WARN 1줄뿐) · 행 칸 = 기준판(seq·ts·to·from·body) / 도구 쪽지(ft2-slack-listen·ft-idle-scan)·#N 없는 보낸 이 = 0
#      / 옛 번호(A#1)·명부 계보(_replaced_by) 앞 쪽지 = 셈 / 같은 역할 [인계] → [레디] = 0
#   ⑩ 같은 본문 두 번 = QUEUED-DUP · recv 순서 LIFO · crossed 칸 없는 옛 행 = 표시 0
# 변이(사본에만): M6 crossed 칸 쓰기 지움 → ⑧ 빨강(받는 쪽) · M7 #N 없는 보낸 이(도구)도 셈 → ⑨ 빨강
# 기준판 = MBOX_SRC=<팩 origin/main 의 harness/comm 사본>(표시 0 = ⑧ Red).
set -uo pipefail   # 실 우편함·실 명부·실 tmux 0(tmux = PATH 스텁) · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${MBOX_SRC:-$HERE/../comm}"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
A="byz-x-arch-pi#2"; A1="byz-x-arch-pi#1"; B="byz-x-plan-pi#1"; OLD="byz-x-oldarch-pi#1"

new_env() {   # 격리 루트 · 빈 큐 · 명부(seats-x.json · OLD → A 계보) · tmux 스텁 · MUT 변이
  E="$(mktemp -d "$T/env.XXXXXX")"; C="$E/comm"; Q="$C/mailbox.jsonl"; S="$E/seats"
  mkdir -p "$C" "$S" "$E/stub" "$E/code"; cp -R "$SRC"/. "$E/code/"; cp "$HERE/../bin/ft-name-lint.sh" "$E/code/" 2>/dev/null; : > "$Q"
  printf '{"_master": "byz-x-master-pi#1"}\n' > "$S/seats.json"
  printf '{"%s": {"role": "arch", "_replaces": ["%s"]}, "%s": {"role": "arch", "_replaced_by": "%s"}, "%s": {"role": "arch", "_replaced_by": "%s"}, "%s": {"role": "planner"}}\n' \
    "$A" "$A1" "$A1" "$A" "$OLD" "$A" "$B" > "$S/seats-x.json"
  printf '%s\n%s\n' "$A" "$B" > "$E/sessions"
  printf '#!/bin/sh\ncat "%s/sessions"\n' "$E" > "$E/stub/tmux"; chmod +x "$E/stub/tmux"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
py() { PATH="$E/stub:$PATH" FT_SEATS_JSON="$S/seats.json" FT_MBOX_DIR="$C" python3 "$E/code/mbox.py" "$@"; }
send() { py send "$1" "$2" "$3" --force >"$E/out" 2>"$E/err"; RC=$?; }
recv() { py recv "$1" >"$E/rout" 2>"$E/rerr"; RRC=$?; }
seq_of() { sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' "$E/out"; }
seed() {   # seed <seq> <to> <from> [본문] — 큐에 행 1개(시험 준비 · 제품 경로 아님)
  printf '{"seq": %d, "ts": "2026-11-15T23:41:%02d", "to": "%s", "from": "%s", "body": "%s"}\n' "$1" "$(( $1 % 60 ))" "$2" "$3" "${4:-seed $1}" >> "$Q"
}
crossed_of() {   # crossed_of <파일> <seq> — 그 행의 crossed 칸(JSON) · 없음 = none
  python3 - "$1" "$2" <<'PY'
import json, sys
for ln in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(ln)
    if r.get("seq") == int(sys.argv[2]):
        print(json.dumps(r.get("crossed"), sort_keys=True) if "crossed" in r else "none")
PY
}
keys_of() { python3 -c 'import json,sys; [print(",".join(sorted(json.loads(l)))) for l in open(sys.argv[1]) if json.loads(l).get("seq")==int(sys.argv[2])]' "$1" "$2"; }

mut_m6() { python3 - "$E/code/mbox_ops.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); old = 'row["crossed"] = cross'
assert old in s; open(p, "w").write(s.replace(old, "pass"))
PY
}
mut_m7() { python3 - "$E/code/mbox_ops.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); old = 'and SEAT_RE.search(r.get("from") or "")'
assert old in s; open(p, "w").write(s.replace(old, ""))
PY
}

eight() {   # ⑧ 보낸 쪽 · 받는 쪽 · 7통
  new_env; send "$A" "$B" "질문 1"; local s1; s1="$(seq_of)"
  send "$B" "$A" "보고 1"; local r1=$RC s2; s2="$(seq_of)"
  local want="엇갈림 $B 가 보낸 안 읽은 쪽지 1통(가장 새 #$s1 "
  local e1 q1 l1; e1="$(grep -c "^${want}[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) — 이 쪽지는 그것을 안 읽고 보낸 글이다 · recv 뒤 어긋나면 정정 1통$" "$E/err")"
  q1="$(crossed_of "$Q" "$s2")"; l1="$(crossed_of "$C/mailbox.log.jsonl" "$s2")"
  recv "$B"; local below; below="$(grep -A1 "^READ \[$A->$B\] #$s2 " "$E/rout" | sed -n 2p)"
  if ! { [ "$r1" = 0 ] && grep -q "^QUEUED seq=$s2 to=$B pending=1 " "$E/out" && [ "$e1" = 1 ] \
     && [ "$q1" = "{\"n\": 1, \"seqs\": [$s1]}" ] && [ "$l1" = "$q1" ] && [ "$below" = "엇갈림 — $A 이 네 쪽지 #$s1(1통)를 안 읽고 보낸 글" ]; }; then
    bad "⑧ r1=$r1 e1=$e1 q1=$q1 l1=$l1 below=[$below] err=$(tr '\n' '|' < "$E/err")"; return 1; fi
  new_env; local i; for i in 1 2 3 4 5 6 7; do send "$A" "$B" "질문 $i"; done; local last; last="$(seq_of)"
  send "$B" "$A" "보고 2"; local s3; s3="$(seq_of)"; recv "$B"
  local nums; nums="$(python3 -c 'import sys; n=int(sys.argv[1]); print(",".join("#%d" % k for k in range(n, n-5, -1)))' "$last")"
  if grep -q "^엇갈림 $B 가 보낸 안 읽은 쪽지 7통(가장 새 #$last " "$E/err" && grep -qx "엇갈림 — $A 이 네 쪽지 $nums(7통)를 안 읽고 보낸 글" "$E/rout"; then
    ok "⑧ A stderr 1줄 · rc 0 · QUEUED 그대로 · 큐·기록 crossed 칸 · B recv READ 아래 1줄 · 7통 = 번호 5개 + (7통)"; return 0; fi
  bad "⑧ 7통 err=$(tr '\n' '|' < "$E/err") rout=$(tr '\n' '|' < "$E/rout")"; return 1
}

nine() {   # ⑨ 세지 않는 것 · 세는 것(계보)
  new_env; send "$B" "$A" "0통 보고"; local s0; s0="$(seq_of)"; local o0 e0 k0 lines0; o0="$(cat "$E/out")"; e0="$(grep -vc '^WARN desk 경로 판정' "$E/err")"   # 기준판도 내는 desk 판정 WARN 1줄(사본에 판정기·명부 없음)만 남는다
  k0="$(keys_of "$Q" "$s0")$(keys_of "$C/mailbox.log.jsonl" "$s0")"; lines0="$(grep -c . "$E/out")"
  if ! { [ "$RC" = 0 ] && [ "$lines0" = 1 ] && [[ "$o0" == "QUEUED seq=$s0 to=$B pending=1 file=$Q bytes="* ]] && [ "$e0" = 0 ] \
     && [ "$k0" = "body,from,seq,to,tsbody,from,seq,to,ts" ]; }; then bad "⑨ 0통 rc=$RC out=[$o0] e0=$e0 k0=$k0"; return 1; fi
  new_env; seed 1601 "$A" ft2-slack-listen "[Slack] 새 업무"; seed 1602 "$A" ft-idle-scan "[idle] 알림"; seed 1603 "$A" byz-x-plan-pi "역할 이름 보낸 이"
  echo 1700 > "$C/.mbox-seq"; send "$B" "$A" "도구 쪽지만"; local st; st="$(seq_of)"
  if ! { [ "$(grep -c '엇갈림' "$E/err")" = 0 ] && [ "$(crossed_of "$Q" "$st")" = none ]; }; then bad "⑨ 도구 err=$(tr '\n' '|' < "$E/err")"; return 1; fi
  new_env; seed 1601 "$A1" "$B" "옛 번호 앞"; seed 1602 "$OLD" "$B" "계보 앞"; echo 1700 > "$C/.mbox-seq"; send "$B" "$A" "계보 보고"; local sl; sl="$(seq_of)"
  if ! [ "$(crossed_of "$Q" "$sl")" = '{"n": 2, "seqs": [1602, 1601]}' ]; then bad "⑨ 계보 crossed=$(crossed_of "$Q" "$sl") err=$(tr '\n' '|' < "$E/err")"; return 1; fi
  new_env; seed 1601 "$A" "$A1" "[인계] $A1 -> $A · 항목 0"; echo 1700 > "$C/.mbox-seq"; send "$A1" "$A" "[레디] $A <- $A1"; local sr; sr="$(seq_of)"
  if [ "$(grep -c '엇갈림' "$E/err")" = 0 ] && [ "$(crossed_of "$Q" "$sr")" = none ]; then
    ok "⑨ 0통 = 출력·행 칸 기준판 · 도구·#N 없는 보낸 이 = 0 · 옛 번호·계보 = 셈(2통) · [인계]→[레디] = 0"; return 0; fi
  bad "⑨ 레디 err=$(tr '\n' '|' < "$E/err")"; return 1
}

ten() {   # ⑩ 불변
  new_env; send "$B" "$A" "같은 본문"; local s1; s1="$(seq_of)"; send "$B" "$A" "같은 본문"; local dup; dup="$(cat "$E/out")"
  new_env; seed 1601 "$A" "$B" "옛 행 1"; seed 1602 "$A" "$B" "옛 행 2"; seed 1603 "$A" "$B" "옛 행 3"; recv "$A"
  local order; order="$(sed -n 's/^READ \[.*\] #\([0-9]*\) .*/\1/p' "$E/rout" | tr '\n' ' ')"
  if [[ "$dup" == "QUEUED-DUP seq=$s1 "* ]] && [ "$(grep -c . "$Q" 2>/dev/null)" = 0 ] && [ "$order" = "1603 1602 1601 " ] && [ "$(grep -c '엇갈림' "$E/rout")" = 0 ]; then
    ok "⑩ 같은 본문 = QUEUED-DUP · recv LIFO · crossed 칸 없는 옛 행 = 표시 0"; return 0; fi
  bad "⑩ dup=[$dup] order=[$order] rout=$(tr '\n' '|' < "$E/rout")"; return 1
}

e=$(date +%s); eight; nine; ten; echo "RUN 사례 $(( $(date +%s) - e ))초"
if [ -z "${MBOX_SRC:-}" ]; then
  echo "--- 변이 대조(빨강이어야 정상 · 원본 결과 = 위 PASS)"
  for m in mut_m6:eight mut_m7:nine; do
    rc=0; ( MUT=${m%:*}; ${m#*:} ) >/dev/null 2>&1 || rc=$?
    if [ "$rc" != 0 ]; then echo "RED-OK ${m%:*} (${m#*:} FAIL)"; else echo "RED-MISS ${m%:*}"; fail=$((fail+1)); fi
  done
fi
echo "결과: fail=$fail"
[ "$fail" = 0 ]
