#!/usr/bin/env bash
# test_nano_record_close_seq_recover_r2272.sh — r2272: landed 의 닫기 요청이 «보낸 뒤 · 장부 기록 전» 에 끊겨도, 다시 실행이 우편 로그에서 그 seq 를 찾아 NEXT
#   ① 1회차 쪽지 큐·로그 뒤 rc 124 → 2회차 ALREADY + INFO «우편 로그에서 찾음» + NEXT --recv <1회차 seq> rc 0 · 2회차 send 0
#   ② 로그 파일 없음 → send 1 · 지금 꼴 · ③ 로그 = 디렉터리 / 깨진 줄만 → «판정 불가 우편 로그» · send 0 · rc 3
#   ④ 같은 좌석 · 같은 stem · 다른 Q 행만 → send 1 · 새 seq · ⑤ 다른 좌석의 같은 stem·Q 행 → send 1 · ⑥ 장부 rec 있음 → 로그 안 읽음 · send 0 · 그 seq
#   ⑦(C4 보강) 1회차 seq 가 버림 원장에 있음 → 고르지 않음 · send 1 · ⑦b r1820 B3(rec 같음 · 기록 seq 버려짐) → found 가 그 행 빼고 send 1
#   ⑦c(DA#27 메모) 버림 원장 판독 실패(Unjudged) → 새 모듈 안에서 «판정 불가» 1줄 · send 0 · rc 3(밖으로 안 올림)
#   기준판(팩 14c99d8c) 대조: ① ③ Red · ② ④ ⑤ ⑥ ⑦ ⑦b 같음 · 변이 M1~M4(+원본 대조)
#   가짜 우편함 감싸개(FT_MBOX) = 픽스처 가짜 mbox + <comm>/mailbox.log.jsonl 1줄(실 꼴) · R2272_CUT=1 = 쓴 뒤 rc 124 · R2272_GUARD=1 = 같은 본문 재발신 BLOCKED rc 3
#   세계 = _nano_record_r1717_fixture.sh(임시 루트·임시 우편함) · 실 우편함·실 좌석·실 리포 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'; BASE_SHA=14c99d8cfcd24e6e4c5c83fc9f28fdfe694e4a88
JL="$COMM/mailbox.log.jsonl"; CALLS="$T/r2272-calls.log"; WM="$T/r2272-mbox.sh"
cat > "$WM" <<EOF
#!/usr/bin/env bash
[ "\$1" = send ] || exec bash "$FK/mbox.sh" "\$@"
printf '%s\t%s\n' "\$3" "\${4%%\$'\n'*}" >> "$CALLS"
if [ "\${R2272_GUARD:-0}" = 1 ] && [ -f "$JL" ] && python3 -c 'import json,sys
sys.exit(0 if any((d.get("from"), d.get("to"), d.get("body")) == tuple(sys.argv[2:5]) for d in map(json.loads, open(sys.argv[1]))) else 1)' "$JL" "\$3" "\$2" "\$4"; then
  echo "BLOCKED 같은 본문 재발신(가드 대역)" >&2; exit 3
fi
out="\$(bash "$FK/mbox.sh" "\$@")" || exit \$?
[ "\${R2272_NOLOG:-0}" = 1 ] || python3 -c 'import json,sys;print(json.dumps({"seq":int(sys.argv[1]),"ts":"t","to":sys.argv[2],"from":sys.argv[3],"body":sys.argv[4]},ensure_ascii=False))' \
  "\$(cat "$COMM/.mbox-seq")" "\$2" "\$3" "\$4" >> "$JL" 2>/dev/null
[ "\${R2272_CUT:-0}" = 1 ] && exit 124
echo "\$out"
EOF
chmod +x "$WM"; export FT_MBOX="$WM"
prep() { S="$1$2"; N="$(NN "$S")"; fresh; rm -rf "$JL" "$COMM/mailbox.drops.log"; : > "$CALLS"; land "$3"; card "$S"; seats "$N|nano|$S"; turn "$3" "$S"; }   # prep <사례> <꼬리표> <PR>
rl() { rec landed --seat "$N" --pr "$1" --card "$S" --test "$TST"; }
ncl() { grep -c "^$N	\[완료·닫기 요청\]" "$CALLS" || true; }   # 그 좌석의 닫기 요청 send 호출 수(가드에 막힌 것 포함)
jrow() { python3 -c 'import json,sys;print(json.dumps({"seq":int(sys.argv[1]),"ts":"t","to":sys.argv[2],"from":sys.argv[3],"body":sys.argv[4]},ensure_ascii=False))' "$@" >> "$JL"; }
lastseq() { cat "$COMM/.mbox-seq"; }
closecell() { python3 -c 'import json,sys
try: print(len(json.load(open(sys.argv[1])).get("close") or {}))
except OSError: print(0)' "$STATE/land-record-notified.json"; }   # 장부 close 칸 열쇠 수

c1() {  # ① 끊김 뒤 다시 실행 = 찾아 채움
  prep c1 "$1" 1; R2272_CUT=1 rl 1; local s1; s1="$(lastseq)"
  t "① 1회차 끊김 rc≠0" [ "$RC" != 0 ]; t "① 1회차 send 1" [ "$(ncl)" = 1 ]; : > "$CALLS"
  R2272_GUARD=1 rl 1
  t "① rc0" [ "$RC" = 0 ]; t "① ALREADY" inc "$OUT" ALREADY; t "① INFO" inc "$OUT" "INFO 닫기 요청 #$s1 우편 로그에서 찾음"
  t "① NOTIFIED 그대로" inc "$OUT" "NOTIFIED 닫기 요청 → $MASTER #$s1"; t "① NEXT recv 1회차 seq" inc "$OUT" "--recv $s1"; t "① 2회차 send 0" [ "$(ncl)" = 0 ]; t "① 빠짐 0" exc "$OUT" "빠짐="; return $E
}
c2() {  # ② 로그 파일 없음 → 지금 길(send 1 · NEXT)
  prep c2 "$1" 2; R2272_NOLOG=1 rl 2
  t "② rc0" [ "$RC" = 0 ]; t "② send 1" [ "$(ncl)" = 1 ]; t "② NEXT" inc "$OUT" "--recv $(lastseq)"; t "② INFO 0" exc "$OUT" "우편 로그에서 찾음"
  t "② NOTIFIED" inc "$OUT" "NOTIFIED 닫기 요청 → $MASTER #$(lastseq)"; t "② 로그 없음 그대로" [ ! -e "$JL" ]; return $E
}
c3() {  # ③ 로그 못 읽음(디렉터리 · 깨진 줄만) → 판정 불가 · send 0 · rc 3
  prep c3 "a$1" 3; mkdir -p "$JL"; rl 3
  t "③a rc3" [ "$RC" = 3 ]; t "③a 판정 불가" inc "$OUT" "판정 불가 우편 로그 읽기"; t "③a send 0" [ "$(ncl)" = 0 ]; t "③a NEXT 0" exc "$OUT" NEXT
  t "③a 판정 불가 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '판정 불가 우편 로그')" = 1 ]; t "③a 빠짐" inc "$OUT" "닫기 명령 보류 빠짐=닫기 요청 seq"
  t "③a 장부 쓰기 0" [ "$(closecell)" = 0 ]
  local ea=$E; prep c3 "b$1" 3; E=$ea; printf 'garbage\n{"seq": 5, broken\n' > "$JL"; rl 3
  t "③b rc3" [ "$RC" = 3 ]; t "③b 판정 불가" inc "$OUT" "판정 불가 우편 로그 깨진 줄만 2줄"; t "③b send 0" [ "$(ncl)" = 0 ]; return $E
}
c4() {  # ④ 같은 좌석 · 같은 stem · 다른 Q(옛 착지) → 찾지 않음 · send 1
  prep c4 "$1" 4; jrow 50 "$MASTER" "$N" "[완료·닫기 요청] $S 착지 0123456789 · 좌석 $N · 세션 기록 x"; rl 4
  t "④ rc0" [ "$RC" = 0 ]; t "④ send 1" [ "$(ncl)" = 1 ]; t "④ NEXT 새 seq" inc "$OUT" "--recv $(lastseq)"; t "④ 50 아님" exc "$OUT" "--recv 50"; return $E
}
c5() {  # ⑤ 다른 좌석의 같은 stem · Q → 찾지 않음 · send 1
  prep c5 "$1" 5; jrow 50 "$MASTER" "$(NN other)" "[완료·닫기 요청] $S 착지 ${Q:0:10} · 좌석 x · 세션 기록 x"; rl 5
  t "⑤ rc0" [ "$RC" = 0 ]; t "⑤ send 1" [ "$(ncl)" = 1 ]; t "⑤ NEXT 새 seq" inc "$OUT" "--recv $(lastseq)"; t "⑤ 50 아님" exc "$OUT" "--recv 50"; return $E
}
c6() {  # ⑥ 장부 rec 있음(정상 2회차) → 로그 안 읽음(디렉터리로 바꿔도) · send 0 · 그 seq
  prep c6 "$1" 6; rl 6; local s1; s1="$(lastseq)"; t "⑥ 1회차 rc0" [ "$RC" = 0 ]; : > "$CALLS"; rm -f "$JL"; mkdir -p "$JL"
  rl 6; t "⑥ rc0" [ "$RC" = 0 ]; t "⑥ send 0" [ "$(ncl)" = 0 ]; t "⑥ NEXT 그 seq" inc "$OUT" "--recv $s1"; t "⑥ 판정 불가 0" exc "$OUT" "판정 불가"; return $E
}
c7() {  # ⑦ 1회차 seq 가 버려짐 → 고르지 않음 · send 1 · 새 seq
  prep c7 "$1" 7; R2272_CUT=1 rl 7; local s1; s1="$(lastseq)"; echo "ts=t seqs=$s1 why=test" > "$COMM/mailbox.drops.log"; : > "$CALLS"
  rl 7; t "⑦ rc0" [ "$RC" = 0 ]; t "⑦ send 1" [ "$(ncl)" = 1 ]; t "⑦ NEXT 새 seq" inc "$OUT" "--recv $(lastseq)"; t "⑦ 옛 seq 아님" [ "$(lastseq)" != "$s1" ]; return $E
}
c7b() {  # ⑦b r1820 B3 — 장부 rec 같음 · 기록 seq 버려짐 → found 가 그 행을 빼고 1회 다시 보냄
  prep c7b "$1" 8; rl 8; local s1; s1="$(lastseq)"; t "⑦b 1회차 rc0" [ "$RC" = 0 ]; echo "ts=t seqs=$s1 why=test" > "$COMM/mailbox.drops.log"; : > "$CALLS"
  rl 8; t "⑦b rc0" [ "$RC" = 0 ]; t "⑦b 버려짐 INFO" inc "$OUT" "우편함에서 버려짐"; t "⑦b send 1" [ "$(ncl)" = 1 ]
  t "⑦b 찾음 0" exc "$OUT" "우편 로그에서 찾음"; t "⑦b NEXT 새 seq" inc "$OUT" "--recv $(lastseq)"; return $E
}
c7c() {  # ⑦c 끊김 뒤 버림 원장 판독 실패 → 새 모듈 안 판정 불가 · send 0 · rc 3
  prep c7c "$1" 9; R2272_CUT=1 rl 9; mkdir -p "$COMM/mailbox.drops.log"; : > "$CALLS"
  rl 9; t "⑦c rc3" [ "$RC" = 3 ]; t "⑦c 판정 불가" inc "$OUT" "판정 불가 우편함 버림 원장"; t "⑦c send 0" [ "$(ncl)" = 0 ]; t "⑦c Traceback 0" exc "$OUT" Traceback
  rmdir "$COMM/mailbox.drops.log"; return $E
}

step "사전: 문법 · 짝 사본"
for f in ft_nano_record_notify.py ft_nano_record_seqfind.py; do
  python3 -m py_compile "$SRC/$f" && ok "py_compile $f" || bad "py_compile $f"; cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 $f cmp0" || bad "짝 사본 $f 다름"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "$f 200줄 안" || bad "$f 200줄 넘음"
done
world
step "반례 ①~⑦c"
run "① 끊김 뒤 다시 실행 = 찾아 채움" c1; run "② 로그 없음 = 지금 길" c2; run "③ 못 읽음 = 판정 불가" c3; run "④ 다른 Q = 안 찾음" c4
run "⑤ 다른 좌석 = 안 찾음" c5; run "⑥ 장부 rec = 로그 안 읽음" c6; run "⑦ 버려진 seq = 안 고름" c7; run "⑦b B3 버려짐 = 한 번 더" c7b; run "⑦c 버림 원장 못 읽음 = 판정 불가" c7c
step "변이 M1~M4 (+원본 대조)"
NP=ft_nano_record_notify.py; SF=ft_nano_record_seqfind.py
mutbin m1 "$NP" '__import__("ft_nano_record_seqfind").found(ctx, r, lambda: ' '(lambda f: f())(lambda: ' && mutcase M1 c1 1 || bad "M1 변이 자리 없음"
mutbin m2 "$SF" "착지 {r['q'][:10]}\"   # r2272-mut:head" "착지 \"   # r2272-mut:head" && mutcase M2 c4 2 || bad "M2 변이 자리 없음"
mutbin m3 "$SF" 'd.get("from") == r["seat"] and ' '' && mutcase M3 c5 3 || bad "M3 변이 자리 없음"
mutbin m4 "$SF" 'raise Unjudged(f"우편 로그 읽기 rc=1 — {type(e).__name__}") from e' 'return []' && mutcase M4 c3 4 || bad "M4 변이 자리 없음"
step "기준판 (팩 ${BASE_SHA:0:10}) — ① ③ Red · ② ④ ⑤ ⑥ ⑦ ⑦b 같음"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft_nano_record_notify.py" ]; then
  for c in c1 c3; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && bad "기준판에서 $c 가 통과함" || ok "기준판 $c FAIL(Red · 기대)"; done
  for c in c2 c4 c5 c6 c7 c7b; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 같음(통과)" || bad "기준판 $c FAIL"; done
else bad "기준판($BASE_SHA) 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
