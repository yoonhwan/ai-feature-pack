#!/usr/bin/env bash
# test_mbox_ring_lead_protect_r1466.sh — r2291(r1466 -r2): 우편함 상한(ring)이 결과·판정 쪽지를 버리지 않고,
# 역할 좌석(명부 _master·_arch·_desk)은 FT_MBOX_RING_LEAD 상한을 쓰며, 버림이 생기면 팀 master 에 «[큐 포화]» 1통(10분 1회).
#   T1 ring=3 · 도구 알림 2 + 좌석 쪽지 2 + [완료 hN](ft-hil-) 1 → 도구 알림 2 버림 · [완료 hN] 남음(회귀 막이)
#   T2 좌석 쪽지 머리 [결과·[레디·[인계·[결정·[회신 = 상한 넘어도 남음(overflow 길) — comm·kit 두 길
#   T3 합성 명부 _master = ring 5(FT_MBOX_RING_LEAD) · 일반 좌석 = 3 · 명부 없음 = 3 — comm·kit 두 길
#   T4 버림 1건 → 팀 master 에 ft-mbox-ring 1통 · 10분 안 재발 0통 · pending < ring 이면 표식 삭제 · master 포화 → harness master — comm·kit
#   T5 좌석 발신 [HIL] 은 보존(#273409 꼴 · 회귀 막이)
#   T6 기존 시험 불변 — keep_human_mail rc0 · mbox_ops.py ≤200줄 · r1116c·r1416 은 기준판 FAIL 줄 밖 새 FAIL 0
#   변이 ① REAL_HEADS 옛 값 → T2 빨강 · ② 역할 상한 끔 → T3 빨강
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 우편함·실 명부 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin/ft-mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
NANO="byz-zz-nano-foo#5"; ARCH="byz-zz-arch-pi#2"; MASTER="byz-zz-master-claude#1"; HMASTER="byz-harness-master-pi#9"

new_env() {   # 격리 루트 + 빈 큐 + 합성 명부(zz 팀 · harness 팀) · 변이함수는 사본에만
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; F="$ENVROOT/.fable-team"; C="$F/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C"; cp "$SRC"/mbox*.py "$C/"; cp "$KIT" "$C/kit.py"; cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"
  : > "$Q"; printf '{}\n' > "$F/seats.json"
  printf '{"_master": "%s", "_arch": "%s", "%s": {"role": "master"}, "%s": {"role": "arch"}, "%s": {"role": "nano"}}\n' \
    "$MASTER" "$ARCH" "$MASTER" "$ARCH" "$NANO" > "$F/seats-zz.json"
  printf '{"_master": "%s", "%s": {"role": "master"}}\n' "$HMASTER" "$HMASTER" > "$F/seats-harness.json"
  if [ -n "${1:-}" ]; then "$1"; fi
}
send() {   # send <comm|kit> <to> <from> <body> — 발신 가드는 이 시험의 관심 밖 → --force
  local prog="$C/mbox.py"; [ "$1" = kit ] && prog="$C/kit.py"
  FT_SEATS_JSON="$F/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING=3 FT_MBOX_RING_LEAD=5 \
    python3 "$prog" send "$2" "$3" "$4" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?
  cat "$ENVROOT/err" >> "$ENVROOT/errs"
}
recv() { local prog="$C/mbox.py"; [ "$1" = kit ] && prog="$C/kit.py"
  FT_SEATS_JSON="$F/seats.json" FT_MBOX_DIR="$C" python3 "$prog" recv "$2" >/dev/null 2>&1; }
pend() { sed -n 's/.*pending=\([0-9]*\).*/\1/p' "$ENVROOT/out" | head -1; }
n_to() { python3 -c 'import json,sys,re;k=lambda n:re.sub(r"#\d+$","",n);print(sum(1 for l in open(sys.argv[1]) if l.strip() and k(json.loads(l)["to"])==k(sys.argv[2]) and (len(sys.argv)<4 or json.loads(l)["from"]==sys.argv[3])))' "$Q" "$@"; }

t1() {   # 회귀 막이(기준판 GREEN)
  new_env; : > "$ENVROOT/errs"
  send comm "$NANO" ft-stall-scan "정체 알림 1"; send comm "$NANO" "$ARCH" "메모 1"
  send comm "$NANO" ft-hil-h48 "[완료 h48] rc=0"; send comm "$NANO" ft-stall-scan "정체 알림 2"; send comm "$NANO" "$ARCH" "메모 2"
  local a b c; a="$(n_to "$NANO" ft-stall-scan)"; b="$(n_to "$NANO" ft-hil-h48)"; c="$(n_to "$NANO" "$ARCH")"
  [ "$a/$b/$c" = "0/1/2" ] && ok "T1 도구 알림부터 버림 · [완료 hN] 남음" || bad "T1 stall/hil/seat=$a/$b/$c (기대 0/1/2)"
}
t2() {   # t2 <comm|kit> [변이]
  new_env "${2:-}"; : > "$ENVROOT/errs"; local h
  for i in 1 2 3; do send "$1" "$NANO" ft-stall-scan "정체 알림 $i"; done
  for h in "[결과]" "[레디]" "[인계]" "[결정]" "[회신]"; do send "$1" "$NANO" "$ARCH" "$h 본문 $h"; done
  local s; s="$(n_to "$NANO" "$ARCH")"
  if [ "$s" = 5 ] && [ "$(n_to "$NANO" ft-stall-scan)" = 0 ] && grep -q '^ERROR 사람 글로 큐 넘침' "$ENVROOT/errs"; then ok "T2[$1] 머리 5개 보존 · overflow ERROR"; return 0; fi
  bad "T2[$1] 남은 좌석 쪽지=$s/5 · 도구=$(n_to "$NANO" ft-stall-scan) · ERROR=$(grep -c '^ERROR' "$ENVROOT/errs")"; return 1
}
t3() {   # t3 <comm|kit> [변이]
  new_env "${2:-}"; : > "$ENVROOT/errs"; local pm pn pq
  for i in 1 2 3 4 5 6; do send "$1" "$MASTER" "$ARCH" "master 앞 메모 $i"; done; pm="$(pend)"
  for i in 1 2 3 4; do send "$1" "$NANO" "$ARCH" "nano 앞 메모 $i"; done; pn="$(pend)"
  for i in 1 2 3 4; do send "$1" "byz-qq-nano-bar#1" "$ARCH" "명부 없는 좌석 메모 $i"; done; pq="$(pend)"
  [ "$pm/$pn/$pq" = "5/3/3" ] && { ok "T3[$1] 역할 좌석 5 · 일반 3 · 명부 없음 3"; return 0; }
  bad "T3[$1] pending master/nano/명부없음=$pm/$pn/$pq (기대 5/3/3)"; return 1
}
t4() {   # t4 <comm|kit>
  new_env; : > "$ENVROOT/errs"; local mk="$F/state/ring-full.byz-zz-nano-foo" a1 a2 h
  for i in 1 2 3 4; do send "$1" "$NANO" "$ARCH" "메모 $i"; done; a1="$(n_to "$MASTER" ft-mbox-ring)"
  send "$1" "$NANO" "$ARCH" "메모 5"; a2="$(n_to "$MASTER" ft-mbox-ring)"
  local body; body="$(grep -o '"body": "\[큐 포화\] to=byz-zz-nano-foo[^"]*' "$Q" | head -1)"
  [ "$a1/$a2" = "1/1" ] && [ -f "$mk" ] && [ -n "$body" ] && ok "T4[$1] 경보 1통 · 10분 안 재발 0 · 표식 있음" \
    || bad "T4[$1] 경보 수 첫/둘째=$a1/$a2 (기대 1/1) · 표식=$([ -f "$mk" ] && echo 있음 || echo 없음) · 본문=${body:-없음}"
  recv "$1" "$NANO"; send "$1" "$NANO" "$ARCH" "비운 뒤 메모"
  [ ! -f "$mk" ] && ok "T4[$1] pending<ring → 표식 삭제(pending=$(pend))" || bad "T4[$1] 비운 뒤도 표식 남음(pending=$(pend))"
  for i in 1 2 3 4 5 6; do send "$1" "$MASTER" "$ARCH" "master 앞 $i"; done; h="$(n_to "$HMASTER" ft-mbox-ring)"
  [ "$h" = 1 ] && ok "T4[$1] master 포화 → harness master 1통" || bad "T4[$1] harness master 경보=$h (기대 1)"
}
t5() {   # 회귀 막이(기준판 GREEN · r1820)
  new_env; : > "$ENVROOT/errs"
  for i in 1 2 3 4; do send comm "$NANO" "$ARCH" "[HIL] 판정 요청 $i"; done
  [ "$(n_to "$NANO" "$ARCH")" = 4 ] && grep -q '^ERROR 사람 글로 큐 넘침' "$ENVROOT/errs" && ok "T5 좌석 발신 [HIL] 4통 보존" \
    || bad "T5 [HIL] 남음=$(n_to "$NANO" "$ARCH")/4"
}
t6() {
  local o; o="$(bash "$HERE/test_mbox_keep_human_mail.sh" 2>&1)" && ok "T6 keep_human_mail rc0" || bad "T6 keep_human_mail $(grep '^FAIL' <<<"$o" | head -3 | tr '\n' ' ')"
  local nl; nl="$(wc -l <"$SRC/mbox_ops.py" | tr -d ' ')"; [ "$nl" -le 200 ] && ok "T6 mbox_ops.py ${nl}줄 ≤200" || bad "T6 mbox_ops.py ${nl}줄"
  # 기준판(6fdbe070) 에서 이미 빨강인 줄 — r1116c = ft_teamset arch-live 의 design/TEAMS.md 없음 · r1416 = mbox_roots.py 209줄(이 카드 밖)
  local t f known
  for t in "test_mbox_ring_unregistered_successor_r1116c:^FAIL (변이가 안 잡힘|ⓓ R7|ⓔ holder)|^FAILED 3$" \
           "test_mbox_bridge_receipt_r1416:^FAIL 200줄 이하 mbox_roots.py|^FAIL=1$"; do
    known="${t#*:}"; t="${t%%:*}"; o="$(bash "$HERE/$t.sh" 2>&1)"
    f="$(grep -E '^FAIL' <<<"$o" | grep -Ev "$known")"
    [ -z "$f" ] && ok "T6 $t 새 FAIL 0(기준판 빨강 줄 $(grep -cE "$known" <<<"$o")개 그대로)" || bad "T6 $t 새 FAIL: $(head -3 <<<"$f" | tr '\n' ' ')"
  done
}
m_heads() { python3 - "$C/mbox_keep.py" "$C/kit.py" <<'PY'
import re, sys
for p in sys.argv[1:]:
    s = open(p, encoding="utf-8").read()
    open(p, "w", encoding="utf-8").write(re.sub(r'^REAL_HEADS = \([^)]*\)', 'REAL_HEADS = ("[완료",)', s, flags=re.M))
PY
}
m_ring() { printf '\nRING_LEAD = MAX_PER_TO\n' >> "$C/mbox_conf.py"; }

t1; t2 comm; t2 kit; t3 comm; t3 kit; t4 comm; t4 kit; t5; t6
f0=$fail
t2 comm m_heads >/dev/null && m1=0 || m1=1
t3 comm m_ring >/dev/null && m2=0 || m2=1
fail=$f0
[ $m1 = 1 ] && ok "변이 ① REAL_HEADS 옛 값 → T2 빨강" || bad "변이 ① 안 잡힘"
[ $m2 = 1 ] && ok "변이 ② 역할 상한 끔 → T3 빨강" || bad "변이 ② 안 잡힘"
echo "결과: fail=$fail"; [ "$fail" -eq 0 ]
