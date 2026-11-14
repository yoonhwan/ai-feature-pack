#!/usr/bin/env bash
# test_mbox_compact_dedupe_r1661.sh — r1661 단계 1: 받는 이 검사(ⓐ) · 큐 정리 = 보관 이동(ⓑ) · 중복 접기(ⓒ) · 수치(ⓓ).
#   ⓐ `--urgent` 받는 이 = REJECT rc2 1줄 · 큐 0 / 명부가 있으면 접두 없는 이름·안 풀리는 이름 거절 · 역할 이름은 통과
#   ⓑ 세션 없음 ∧ 계보 끝 세션 없음 ∧ 14일 = 보관 파일로 이동 · 계보 끝 생존·최근·생존 좌석 행은 그대로 · tmux 실패 = 이동 0
#   ⓒ 같은 받는 이·보낸 이·본문 지문(골 표 뺀) = QUEUED-DUP seq=<원래> dup=N · [HIL]·오빠·[인계]·[레디] 머리는 안 접음
#   ⓓ 실측 꼴 tmp 큐(행 400 · 받는 이 200) 정리 뒤 큐 행 수 ≤ 살아 있는 계보 행 수 · recv(빈 함) ≤ 0.3초
#   R1(DA#10 HOLD) 같은 역할 현역 둘(arch#1·#2 · _replaces [])에 같은 본문 = 둘 다 새 행 · #2 recv 가 읽는다(r1225)
# 변이(사본에만): M1 계보 끝 생존 검사 삭제 → ⓑ 빨강 · M2 [HIL] 예외 삭제 → ⓒ 빨강 · M3 역할 키로 접기 → R1 빨강
set -uo pipefail   # 정본 .py 를 임시 폴더에 복사해 돈다 — 실 큐·실 tmux 0(tmux = PATH 스텁)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
M="byz-x-master-claude#1"; OLD="2026-01-01T00:00:00"

new_env() {   # 격리 루트 · 빈 큐 · 명부(seats-x.json = 좌석 행) · tmux 스텁(세션 = $ENVROOT/sessions) · MUT 변이
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"; S="$ENVROOT/seats"
  mkdir -p "$C" "$S" "$ENVROOT/stub"; cp "$SRC"/mbox*.py "$C/"; cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"; : > "$Q"
  printf '{"_master": "%s"}\n' "$M" > "$S/seats.json"
  printf '{"%s": {"role": "master"}, "byz-x-old": {"_replaced_by": "byz-x-arch-pi#5"}, "byz-x-arch-pi#5": {"role": "arch"}}\n' "$M" > "$S/seats-x.json"
  printf '%s\n' "$M" > "$ENVROOT/sessions"
  printf '#!/bin/sh\n[ -f "%s/tmux-fail" ] && exit 1\ncat "%s/sessions"\n' "$ENVROOT" "$ENVROOT" > "$ENVROOT/stub/tmux"; chmod +x "$ENVROOT/stub/tmux"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
py() { PATH="$ENVROOT/stub:$PATH" FT_SEATS_JSON="$S/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" "$@"; }
send() { py send "$1" "$2" "$3" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?; }
rows() { grep -c . "$Q"; }
seed() {   # seed <seq> <to> [ts] — 큐에 행 1개를 바로 쓴다(시험 준비 · 제품 경로 아님)
  printf '{"seq": %d, "ts": "%s", "to": "%s", "from": "byz-x-nano-a#0", "body": "seed %d"}\n' "$1" "${3:-$OLD}" "$2" "$1" >> "$Q"
}

mut_m1() { sed -i '' 's/^        if memo\[to\] in live:$/        if False:/' "$C/mbox_compact.py"; grep -q '^        if False:$' "$C/mbox_compact.py"; }
mut_m3() { sed -i '' 's/^        if r.get("to") == to and/        if role_key(r.get("to")) == role_key(to) and/' "$C/mbox_compact.py"; grep -q '^        if role_key(r.get' "$C/mbox_compact.py"; }
mut_m2() { sed -i '' 's/^    if _keep(frm, body):$/    if False:/' "$C/mbox_compact.py"; grep -q '^    if False:$' "$C/mbox_compact.py"; }

a() {
  new_env
  send --urgent byz-x-nano-a#0 "본문"; local r1=$RC n1 l1 q1; n1="$(grep -c '^REJECT 받는 이 --urgent' "$ENVROOT/err")"; l1="$(grep -c . "$ENVROOT/err")"; q1="$(rows)"
  send dispatch byz-x-nano-a#0 "본문"; local r2=$RC; send byz-x-ghost-claude byz-x-nano-a#0 "본문"; local r3=$RC
  send byz-x-master-claude byz-x-nano-a#0 "역할 이름"; local r4=$RC
  if [ "$r1" = 2 ] && [ "$n1" = 1 ] && [ "$l1" = 1 ] && [ "$q1" = 0 ] && [ "$r2" = 2 ] && [ "$r3" = 2 ] && [ "$r4" = 0 ] && [ "$(rows)" = 1 ]; then
    ok "ⓐ --urgent rc2 REJECT 1줄 · 큐 0 · dispatch·안 풀리는 이름 rc2 · 역할 이름 QUEUED"; return 0
  fi
  bad "ⓐ r1=$r1 n1=$n1 l1=$l1 q1=$q1 r2=$r2 r3=$r3 r4=$r4 rows=$(rows)"; return 1
}

b() {
  new_env; echo "byz-x-arch-pi#5" >> "$ENVROOT/sessions"
  seed 1601 byz-x-dead-pi#3                        # 이동
  seed 1602 byz-x-old                              # 계보 끝(arch#5) 생존 → 남음
  seed 1603 byz-x-dead-pi#3 "$(date +%Y-%m-%dT%H:%M:%S)"   # 최근 → 남음
  seed 1604 "$M"                                   # 생존 좌석 → 남음
  echo 1700 > "$C/.mbox-seq"; send "$M" byz-x-nano-a#0 "정리 계기"
  local ar; ar="$(cat "$C"/mailbox.archive-*.jsonl 2>/dev/null)"; if [ "$RC" = 0 ] && grep -q '"seq": 1601' <<<"$ar" && [ "$(grep -c . <<<"$ar")" = 1 ] && ! grep -q '"seq": 1601' "$Q" \
     && [ "$(rows)" = 4 ] && grep -q '^ARCHIVED 1 rows' "$ENVROOT/err"; then :; else bad "ⓑ rc=$RC ar=[$ar] rows=$(rows) err=$(tr '\n' ' ' < "$ENVROOT/err")"; return 1; fi
  new_env; seed 1601 byz-x-dead-pi#3; echo 1700 > "$C/.mbox-seq"; : > "$ENVROOT/tmux-fail"; send "$M" byz-x-nano-a#0 "정리 계기"
  if [ "$RC" = 0 ] && grep -q '"seq": 1601' "$Q" && ! ls "$C"/mailbox.archive-* >/dev/null 2>&1 && grep -q '^NOTE 큐 정리 판정 불가' "$ENVROOT/err"; then
    ok "ⓑ 죽은 행 1개만 보관 이동 · 계보 끝 생존·최근·생존 좌석 남음 · tmux 실패 = 이동 0 + NOTE 1줄"; return 0; fi
  bad "ⓑ tmux-fail rc=$RC rows=$(rows) err=$(tr '\n' ' ' < "$ENVROOT/err")"; return 1
}

c() {
  new_env; : > "$C/.queue-swept"
  local G1 G2; G1=$'★골 표 A6 (판본 1)★\n| a | b |\n★/골 표★'; G2=$'★골 표 A6 (판본 2)★\n| c | d |\n★/골 표★'
  send "$M" byz-x-nano-a#0 $'[완료] 같은 보고\n'"$G1"; local s1; s1="$(grep -oE 'seq=[0-9]+' "$ENVROOT/out" | cut -d= -f2)"
  send "$M" byz-x-nano-a#0 $'[완료] 같은 보고\n'"$G2"; local o2 o3; o2="$(cat "$ENVROOT/out")"; send "$M" byz-x-nano-a#0 $'[완료] 같은 보고\n'"$G1"; o3="$(cat "$ENVROOT/out")"
  send "$M" byz-x-nano-b#0 $'[완료] 같은 보고\n'"$G1"   # 다른 보낸 이 = 새 행
  for b in "[HIL] 승인 필요" "[HIL] 승인 필요" "[요청·오빠 지시] 같은 글" "[요청·오빠 지시] 같은 글" "[인계] 같은 글" "[인계] 같은 글" "[레디] 같은 글" "[레디] 같은 글"; do send "$M" byz-x-nano-a#0 "$b"; done
  if [ "$o2" = "QUEUED-DUP seq=$s1 dup=1 to=$M" ] && [ "$o3" = "QUEUED-DUP seq=$s1 dup=2 to=$M" ] && [ "$(rows)" = 10 ] \
     && grep -q "\"seq\": $s1,.*\"dup\": 2" "$Q" && [ "$(grep -c '\[HIL\] 승인 필요' "$Q")" = 2 ] && [ "$(grep -c '\[레디\] 같은 글' "$Q")" = 2 ]; then
    ok "ⓒ 골 표만 다른 같은 본문 = QUEUED-DUP seq=$s1 dup=1·2 · 다른 보낸 이·[HIL]·오빠 지시·[인계]·[레디]는 새 행(큐 10)"; return 0; fi
  bad "ⓒ o2=[$o2] o3=[$o3] rows=$(rows)"; return 1
}
r1() {   # DA#10 HOLD R1 반례 — 다른 현역 수신자는 섞지 않는다
  new_env; : > "$C/.queue-swept"; local A=byz-x-arch-pi#1 B=byz-x-arch-pi#2
  printf '{"%s": {"role": "arch", "_replaces": []}, "%s": {"role": "arch", "_replaces": []}}\n' "$A" "$B" > "$S/seats-x.json"
  send "$A" byz-x-nano-r#0 "[완료] 같은 보고"; send "$B" byz-x-nano-r#0 "[완료] 같은 보고"; local o2; o2="$(cat "$ENVROOT/out")"
  py recv "$B" > "$ENVROOT/recv" 2>/dev/null
  if [ "${o2#QUEUED seq=}" != "$o2" ] && grep -q "^READ \[byz-x-nano-r#0->$B\] .*같은 보고" "$ENVROOT/recv"; then ok "R1 같은 역할 현역 둘 = 둘 다 새 행 · #2 recv 가 읽음"; return 0; fi
  bad "R1 o2=[$o2] recv=$(tr '\n' ' ' < "$ENVROOT/recv")"; return 1
}
d() {
  new_env
  python3 - "$Q" "$ENVROOT/sessions" "$S/seats-x.json" <<'SEED'
import json, sys
q, sess, seats = sys.argv[1:4]
doc = json.load(open(seats)); live = []
with open(q, "w") as f:
    for i in range(200):   # 받는 이 200 × 2행 = 400 · 앞 20 = 생존 · 다음 10 = 옛 이름(계보 끝 생존)
        to = "byz-x-s%d-pi#%d" % (i, i)
        if i < 20: live.append(to)
        elif i < 30: to = "byz-x-r%d" % i; doc[to] = {"_replaced_by": "byz-x-t%d-pi#1" % i}; live.append("byz-x-t%d-pi#1" % i)
        for k in range(2):
            f.write(json.dumps({"seq": 2000 + i * 2 + k, "ts": "2026-01-01T00:00:00", "to": to, "from": "ft-tick", "body": "n %d %d" % (i, k)}) + "\n")
json.dump(doc, open(seats, "w")); open(sess, "a").write("\n".join(live) + "\n")
SEED
  echo 3000 > "$C/.mbox-seq"
  send "$M" byz-x-nano-a#0 "정리 계기"; local after; after="$(rows)"   # 살아 있는 계보 행 = 30 받는 이 × 2 + 계기 1
  local t; t="$(python3 - "$C" "$S" "$ENVROOT/stub" <<'TIME'
import os, subprocess, sys, time
c, s, stub = sys.argv[1:4]
env = dict(os.environ, PATH=stub + ":" + os.environ["PATH"], FT_SEATS_JSON=s + "/seats.json", FT_MBOX_DIR=c)
t0 = time.time(); subprocess.run([sys.executable, c + "/mbox.py", "recv", "byz-x-empty-pi#9"], env=env, capture_output=True)
print("%.3f" % (time.time() - t0))
TIME
)"
  if [ "$after" = 61 ] && python3 -c "import sys; sys.exit(0 if float('$t') <= 0.3 else 1)"; then
    ok "ⓓ 400행 → 정리 뒤 $after 행(살아 있는 계보 61) · recv(빈 함) ${t}초 ≤ 0.3"; return 0
  fi
  bad "ⓓ after=$after recv=${t}s"; return 1
}

e=$(date +%s); a; b; c; r1; d; echo "RUN 사례 $(( $(date +%s) - e ))초"
echo "--- 변이 대조(빨강이어야 정상)"
for m in mut_m1:b mut_m2:c mut_m3:r1; do   # 변이:사례
  rc=0; ( MUT=${m%:*}; ${m#*:} ) >/dev/null 2>&1 || rc=$?; m=${m%:*}
  if [ "$rc" != 0 ]; then echo "RED-OK $m"; else echo "RED-MISS $m"; fail=$((fail+1)); fi
done
echo "결과: fail=$fail"
[ "$fail" = 0 ]
