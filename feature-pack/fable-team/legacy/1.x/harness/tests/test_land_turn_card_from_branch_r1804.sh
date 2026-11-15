#!/usr/bin/env bash
# test_land_turn_card_from_branch_r1804.sh — r1804: 착지 카드 토큰 = head 가지 마지막 조각 r<N>[a-z]?- (없으면 제목) · 본문 0 · 카드 이름 대조 = «<토큰>-» 로 시작할 때만
#   세계 = _nano_record_r1717_fixture.sh(카드 리포 ROOT · 착지 리포 PACK · 가짜 명부·mbox·tmux) · ft-merge-land.sh 의 실제 호출 줄(:fm_land_notify_land · fm_land_notify_d2)을 떼어 eval
#   fm_land_notify = 대역(쪽지 «카드» 칸만 기록) · D2 Slack = 가짜 scope_slack_post · «정리 차례» 쪽지 = 실 ft-nano-record notify(가짜 mbox) · 실 gh·실 장부·네트워크·sleep 0
#   R1804_BIN = 시험할 bin(기본 추적본) · 변이 M1~M5 = bin 사본에서만 + 원본 대조 1회
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
B0="${R1804_BIN:-$SRC}"; NS=byz-harness-nano-r17; L="$STATE/land-record-turn.jsonl"
step "세계"
world
for s in r1775-r336-a r1777-r336-b r1778-r336-c r1783-a r1787-b r1798b-memory; do cardf "$s"; done; cpush
seats "${NS}75#0|nano|r1775-r336-a" "${NS}77#0|nano|r1777-r336-b" "${NS}78#0|nano|r1778-r336-c"
cards_of() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
  d=json.loads(l)
  if d["pr"]==int(sys.argv[2]): print(" ".join(sorted(c.rsplit("/",1)[-1][:-3] for c in d["cards"])))' "$L" "$1"; }
ctok() { ( . "$1/ft-merge-lib.sh" >/dev/null 2>&1; fm_card_tokens "$2" "$3" ); }
call_land() {  # call_land <bin> <PR> <head> <제목> <본문> — ft-merge-land 의 실제 착지 알림 줄 · NOTE = 쪽지 줄
  local b="$1" c; c="$(grep -m1 '^fm_land_notify_land ' "$b/ft-merge-land.sh" | sed 's/; HLTO=.*//')"; land "$2"; : > "$T/note"
  ( . "$b/ft-merge-lib.sh" >/dev/null 2>&1
    fm_land_notify() { printf '%s | %s\n' "$2" "$(shift 2; printf '%s ' "$@")" >>"$T/note"; }
    PH_="$3" PT="$4" PB="$5"; pf() { case "$1" in headRefName) printf '%s' "$PH_";; title) printf '%s' "$PT";; body) printf '%s' "$PB";; esac; }
    PR="$2" M="$(g "$PACK" rev-parse "$Q^")" HEADSHA="$PH" REPO="$PACK" TARGET=main irc=0 IOUT='OK n=1'
    eval "$c" ) >"$T/land.out" 2>&1
  NOTE="$(cat "$T/note")"
}
call_d2() {  # call_d2 <bin> <PR> <head> <제목> <본문> — ft-merge-land 의 실제 D2 알림 호출 · SL = Slack 본문
  local b="$1" c; c="$(grep -m1 -o 'fm_land_notify_d2 "\$PR"[^#]*' "$b/ft-merge-land.sh")"; mkdir -p "$T/d2"; : > "$T/slack"
  printf 'scope_slack_post() { printf "%%s\\n" "$1" >> "%s"; }\n' "$T/slack" > "$T/d2/ft-autonomy-scope.sh"
  ( . "$b/ft-merge-lib.sh" >/dev/null 2>&1; FM_HERE="$T/d2"
    PH_="$3" PT="$4" PB="$5"; pf() { case "$1" in headRefName) printf '%s' "$PH_";; title) printf '%s' "$PT";; body) printf '%s' "$PB";; esac; }
    PR="$2" Q=deadbeefcafe; eval "$c" ) >/dev/null 2>&1
  SL="$(cat "$T/slack")"
}
c1() {  # ① PR 1002 재연 — 장부 cards = r1777 1장 · «정리 차례» = r1777 좌석에만
  fresh; call_land "$1" 1002 nano/r1777-switch-window-autonomy-event 'fix(r1777): 전환 창 자율 이벤트' '(R336 · 리뷰) r1675 r1694 · 겹침 r1775 r1778'
  t "① 장부 cards = r1777 1장" [ "$(cards_of 1002)" = r1777-r336-b ]
  t "① 쪽지 카드 칸 = r1777" inc "$NOTE" "카드 r1777 · 설치"
  t "① 정리 차례 r1777 좌석 1통" [ "$(nto "${NS}77#0" '\[정리 차례\]')" = 1 ]
  t "① r1775·r1778 좌석 0통" [ "$(nto "${NS}75#0")$(nto "${NS}78#0")" = 00 ]; return $E
}
c1b() {  # ①b A5 — 이름이 «<토큰>-» 로 시작할 때만
  E=0; local o; o="$( ( . "$1/ft-merge-lib.sh" >/dev/null 2>&1; fm_cards_by_tokens "$ROOT" r336 ) 2>/dev/null)"
  t "①b r336 → 0줄" [ -z "$o" ]
  o="$( ( . "$1/ft-merge-lib.sh" >/dev/null 2>&1; fm_cards_by_tokens "$ROOT" r1777 ) 2>/dev/null)"
  t "①b r1777 → r1777-r336-b 1줄" [ "$o" = "$ROOT/$IDX/진행/r1777-r336-b.md" ]; return $E
}
c1m() {  # ①m 가지 토큰이 있으면 제목의 다른 번호는 안 더함(M2·M3)
  E=0; t "①m 가지 r1777 · 제목 (r1777 · r1775 후속) → r1777" [ "$(ctok "$1" nano/r1777-x '(r1777 · r1775 후속)')" = r1777 ]; return $E
}
c2() {  # ② 가지에 번호 없음 → 제목 토큰(나온 순서) · 본문 0
  fresh; t "② fm_card_tokens = r1783 r1787" [ "$(ctok "$1" docs/arch-bundle 'close r1783 r1787 r1783')" = "r1783 r1787" ]
  t "② 순서 = 제목에 나온 순서" [ "$(ctok "$1" docs/arch-bundle 'close r1787 r1783')" = "r1787 r1783" ]
  call_land "$1" 1003 docs/arch-bundle 'close r1783 r1787' '겹침 r1775 r1778'
  t "② 장부 cards = r1783 r1787" [ "$(cards_of 1003)" = "r1783-a r1787-b" ]
  t "② 쪽지 카드 칸 = r1783 r1787" inc "$NOTE" "카드 r1783 r1787 · 설치"; return $E
}
c3() {  # ③ 가지·제목 모두 번호 없음 → cards:[] · «카드 없음» 그대로
  fresh; t "③ fm_card_tokens 빈 출력" [ -z "$(ctok "$1" chore/x '코드만')" ]
  call_land "$1" 1004 chore/x '코드만' '본문 r1777'
  t "③ 장부 cards = [] 1줄" [ "$(grep -c '"pr": 1004, .*"cards": \[\]' "$L")" = 1 ]
  t "③ 쪽지 «카드 없음»" inc "$NOTE" "카드 없음 · 설치"; return $E
}
c4() {  # ④ D2 착지 · ① 입력 → Slack «카드 r1777»
  E=0; call_d2 "$1" 1002 nano/r1777-switch-window-autonomy-event 'fix(r1777): 전환 창' '(R336) r1675 r1775 r1778'
  t "④ Slack «카드 r1777 · DA APPROVE»" inc "$SL" "병합함: PR #1002 · 카드 r1777 · DA APPROVE"; return $E
}
c5() {  # ⑤ 접미 글자 그대로
  fresh; t "⑤ fm_card_tokens = r1798b" [ "$(ctok "$1" nano/r1798b-memory-store-core 'r1798b 메모리')" = r1798b ]
  call_land "$1" 1005 nano/r1798b-memory-store-core 'r1798b 메모리' '본문'
  t "⑤ 장부 cards = r1798b-memory" [ "$(cards_of 1005)" = r1798b-memory ]; return $E
}
step "사례 ①~⑤ (원본 $B0)"
for c in c1 c1b c1m c2 c3 c4 c5; do run "$c" "$c" "$B0"; done
step "짝 사본"
cmp -s "$SRC/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"; eq "bin·kit cmp0(ft-merge-lib)" $? 0
cmp -s "$SRC/ft-merge-land.sh" "$KIT/ft-merge-land.sh"; eq "bin·kit cmp0(ft-merge-land)" $? 0
mut() {  # mut <M> <사례> <파일> <옛> <새> — bin 사본 1개 → 그 사례 FAIL 이어야 · 원본으로 같은 사례 1회 더
  local d="$T/mut-$1" o; rm -rf "$d"; cp -R "$B0" "$d"
  python3 - "$d/$3" "$4" "$5" <<'PY' || { bad "$1 변이 자리 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
sys.exit(1) if s.count(a) != 1 else open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if o="$("$2" "$d" 2>&1)"; then bad "$1 변이를 못 잡음($2)"; else ok "$1 변이 → $2 FAIL(잡힘) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
  if o="$("$2" "$B0" 2>&1)"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조 FAIL($2)" "$o"; fi
}
step "변이 M1~M5"
mut M1 c2 ft-merge-land.sh '"$(pf title)" "$irc"' '"$(pf title) $(pf body)" "$irc"'
mut M2 c1m ft-merge-lib.sh 'grep -oE '"'"'^r[0-9]{2,5}[a-z]?-'"'"')"' 'grep -oE '"'"'^NOPE'"'"')"'
mut M3 c1m ft-merge-lib.sh '&& { printf '"'"'%s'"'"' "${t%-}"; return 0; }' '&& printf '"'"'%s '"'"' "${t%-}"'
mut M4 c4 ft-merge-land.sh 'fm_land_notify_d2 "$PR" "$Q" "$(pf headRefName)" "$(pf title)"' 'fm_land_notify_d2 "$PR" "$Q" "$(pf title) $(pf body)"'
mut M5 c1b ft-merge-lib.sh 'case "$b" in "$t"-*)' 'case "-$b" in *"-$t-"*)'
finish
