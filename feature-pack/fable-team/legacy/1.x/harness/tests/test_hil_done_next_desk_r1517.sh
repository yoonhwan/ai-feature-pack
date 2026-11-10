#!/usr/bin/env bash
# test_hil_done_next_desk_r1517.sh — r1517: ft-hil-notify.sh done 이 ①화면 끝에 «남은 미실행 h + 다음 실행 줄» 을 찍고 ②[완료] 쪽지 수신자에
# seats-planner.json _desk 를 _master 와 같이 더하며 ③본문 끝에 «남은 N · 다음 h<M>» 꼬리를 붙이는지(카드 A · 사례 ⓐ~ⓕ).
# 격리: 임시 폴더의 h 진입 파일 4종(h1 끝 · h2·h3 미실행 · h4 .held 보류) + 가짜 쪽지함(mbox.sh = 받은 to·본문을 파일에 적음)
#       + 가짜 seats-planner.json(_master · _desk) — 실 /tmp/h* · 실 우편함 · 실 git 0 · 자기 재호출 0 · 고정 sleep 0.
# ⓖ(r1517 HOLD aifp#796): mbox send 실패 때 stderr 에 «이유(첫 줄) + rc» 를 남긴다 — 가짜 mbox 가 «REJECT 이유X» rc3.
# 변이 대조: M1 _desk 수신 줄 삭제 → ⓑ FAIL · M2 목록 호출 삭제 → ⓐ FAIL · M3 보류 필터 무시(--held 추가) → ⓐ FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../bin/ft-hil-notify.sh"
BIN="${FT_HIL_NOTIFY_BIN:-$SRC}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
s=$(date +%s)

world() {  # <폴더> <_master> [_desk] — comm/mbox.sh(= to·본문 적기) · seats-planner.json · hil/ 폴더
  mkdir -p "$1/comm" "$1/hil"
  cat > "$1/comm/mbox.sh" <<'SH'
#!/usr/bin/env bash
d="$(cd -- "$(dirname -- "$0")" && pwd)"; printf '%s\t%s\n' "$2" "$4" >> "$d/sent"
SH
  if [ -n "${3:-}" ]; then printf '{"_master":"%s","_desk":"%s"}\n' "$2" "$3" > "$1/seats-planner.json"
  else printf '{"_master":"%s"}\n' "$2" > "$1/seats-planner.json"; fi
}
mk_h() { printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s/%s.plan\n' "$1" "$2" > "$1/$2"; printf '=== 결과 === %s\n' "${3:-OK}" > "$1/$2.out"; }
fin() {  # <폴더> <h> — 실행이 끝난 h(.ran 마지막 줄 = rc 행) = 목록에서 빠진다
  printf '%s\nrc=0 %s\n' "$(date +%s)" "$(date +%s)" > "$1/$2.ran"; }
run() {  # <bin> <world> <좌석…> → RC·OUT·ERR·SENT·BODY
  local b="$1" w="$2" rc; shift 2
  rm -f "$w/comm/sent"
  env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" bash "$b" done "$w/hil/h1" 0 "$w/comm" "$@" >"$T/out" 2>"$T/err"; rc=$?
  RC="$rc"; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
  SENT="$(cut -f1 "$w/comm/sent" 2>/dev/null | tr '\n' ' ')"; BODY="$(tail -1 "$w/comm/sent" 2>/dev/null | cut -f2)"
}
lines() { printf '%s\n' "$1" | grep -c . ; }

# ── ⓐ 화면 블록 = 남은 미실행 목록(보류 제외) + 다음 실행 줄 · ⓑ 수신자 · ⓒ 본문 꼬리 ──
w="$T/a"; world "$w" 'byz-planner-master-pi#9' 'byz-planner-desk-pi#125'
mk_h "$w/hil" h1 'p1 끝'; fin "$w/hil" h1
mk_h "$w/hil" h2; mk_h "$w/hil" h3; mk_h "$w/hil" h4
printf 'hold %s byz-x 사유\n' "$(date +%s)" > "$w/hil/h4.held"
run "$BIN" "$w" 'byz-harness-master-pi#171'

echo "== ⓐ 화면: 남은 미실행 h 2(h4 보류 제외) + 다음 실행 줄 h2 · 2줄 · rc0"
[ "$RC" = 0 ] && ok "ⓐ rc0" || bad "ⓐ rc=$RC $(cat "$T/err")"
printf '%s\n' "$OUT" | sed -n 1p | grep -Eq '^남은 미실행 h 2: h2\([0-9]+분\) h3\([0-9]+분\)$' && ok "ⓐ 1줄 = $(printf '%s\n' "$OUT" | sed -n 1p)" || bad "ⓐ 1줄: «$(printf '%s\n' "$OUT" | sed -n 1p)»"
[ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "다음 실행 줄 = ! bash $w/hil/h2" ] && ok "ⓐ 2줄 = 다음 실행 줄 h2" || bad "ⓐ 2줄: «$(printf '%s\n' "$OUT" | sed -n 2p)»"
[ "$(lines "$OUT")" = 2 ] && ok "ⓐ 블록 = 2줄(그 밖 stdout 0)" || bad "ⓐ stdout $(lines "$OUT")줄: $OUT"
echo "== ⓑ 수신 = 요청 좌석 + _master + _desk 각 1통 · stderr 0"
[ "$SENT" = "byz-harness-master-pi#171 byz-planner-master-pi#9 byz-planner-desk-pi#125 " ] && ok "ⓑ 3통 = $SENT" || bad "ⓑ 수신: «${SENT}»"
[ -z "$ERR" ] && ok "ⓑ stderr 0" || bad "ⓑ stderr: $ERR"
echo "== ⓒ 본문 = [완료 h1] rc=0 · 결과 · 계획 + 꼬리 «남은 2 · 다음 h2»"
case "$BODY" in "[완료 h1] rc=0 · === 결과 === p1 끝 · 계획 $w/hil/h1.plan · 남은 2 · 다음 h2") ok "ⓒ 본문 = $BODY";; *) bad "ⓒ 본문: «${BODY}»";; esac

# ── ⓐ2 다음 줄 후보 = 번호가 가장 작은 «.ran 없는» h (h10 은 중단분이라 목록에만) ──
w="$T/a2"; world "$w" 'plz-master#9' 'plz-desk#1'
mk_h "$w/hil" h1; fin "$w/hil" h1; mk_h "$w/hil" h2; mk_h "$w/hil" h10; printf '%s\n' "$(date +%s)" > "$w/hil/h10.ran"
run "$BIN" "$w" 'req#1'
[ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "남은 미실행 h 2: h10(0분) h2(0분)" ] && ok "ⓐ2 목록 = h10·h2(중단분도 보인다)" || bad "ⓐ2 1줄: «$(printf '%s\n' "$OUT" | sed -n 1p)»"
[ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "다음 실행 줄 = ! bash $w/hil/h2" ] && ok "ⓐ2 다음 = h2(10진 최소 · .ran 제외)" || bad "ⓐ2 2줄: «$(printf '%s\n' "$OUT" | sed -n 2p)»"
case "$BODY" in *" · 남은 2 · 다음 h2") ok "ⓐ2 꼬리 = 남은 2 · 다음 h2";; *) bad "ⓐ2 꼬리: «${BODY}»";; esac

# ── ⓓ 남은 미실행 0 → «남은 미실행 h 0» 1줄 · 다음 줄 0 · 본문 꼬리 0 ──
w="$T/d"; world "$w" 'plz-master#9' 'plz-desk#1'
mk_h "$w/hil" h1; fin "$w/hil" h1
run "$BIN" "$w" 'req#1'
[ "$OUT" = "남은 미실행 h 0" ] && ok "ⓓ stdout = «남은 미실행 h 0» 1줄" || bad "ⓓ stdout: «${OUT}»"
case "$BODY" in *"남은"*) bad "ⓓ 꼬리가 붙었다: «${BODY}»";; *) ok "ⓓ 본문 꼬리 0(남은 0 = 붙이지 않는다)";; esac
[ "$SENT" = "req#1 plz-master#9 plz-desk#1 " ] && ok "ⓓ 수신 3통 그대로" || bad "ⓓ 수신: «${SENT}»"

# ── ⓔ 명부에 _desk 없음 → 기존처럼 2통 · 경고 0 · 블록 그대로 ──
w="$T/e"; world "$w" 'plz-master#9'
mk_h "$w/hil" h1; mk_h "$w/hil" h2
run "$BIN" "$w" 'req#1'
[ "$SENT" = "req#1 plz-master#9 " ] && ok "ⓔ 수신 2통 = $SENT" || bad "ⓔ 수신: «${SENT}»"
[ -z "$ERR" ] && ok "ⓔ stderr 0(_desk 없음은 경고 아님)" || bad "ⓔ stderr: $ERR"
[ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "다음 실행 줄 = ! bash $w/hil/h1" ] && ok "ⓔ 화면 블록 그대로" || bad "ⓔ stdout: «${OUT}»"

# ── ⓕ 목록 읽기 실패(폴더 권한 0 = ft_hil_pending rc3) → stderr «판정 불가» 1줄 · 블록 0 · 쪽지는 그대로 ──
w="$T/f"; world "$w" 'plz-master#9' 'plz-desk#1'
mk_h "$w/hil" h1; mk_h "$w/hil" h2
chmod 000 "$w/hil"
run "$BIN" "$w" 'req#1'
chmod 755 "$w/hil"
[ -z "$OUT" ] && ok "ⓕ 블록 0(«0개» 로 쓰지 않는다)" || bad "ⓕ stdout: «${OUT}»"
[ "$(lines "$ERR")" = 1 ] && case "$ERR" in "ft-hil-notify 판정 불가 — 미실행 h 목록 읽기 실패(rc=3): $w/hil") ok "ⓕ stderr 판정 불가 1줄";; *) bad "ⓕ stderr: $ERR";; esac || bad "ⓕ stderr $(lines "$ERR")줄: $ERR"
[ "$SENT" = "req#1 plz-master#9 plz-desk#1 " ] && ok "ⓕ 쪽지는 그대로 3통" || bad "ⓕ 수신: «${SENT}»"
[ "$RC" = 0 ] && ok "ⓕ done rc0(진입 파일 rc 는 부르는 쪽이 정한다)" || bad "ⓕ rc=$RC"

# ── ⓖ mbox send 실패(«REJECT 이유X» rc3) → stderr 에 이유 첫 줄 + rc · done rc1 ──
w="$T/g"; world "$w" 'plz-master#9' 'plz-desk#1'
mk_h "$w/hil" h1; fin "$w/hil" h1; mk_h "$w/hil" h2
cat > "$w/comm/mbox.sh" <<'SH'
#!/usr/bin/env bash
echo "REJECT 이유X"
exit 3
SH
run "$BIN" "$w" 'req#1'
[ "$RC" = 1 ] && ok "ⓖ done rc1(발신 실패)" || bad "ⓖ rc=$RC"
case "$ERR" in *"rc=3"*"REJECT 이유X"*) ok "ⓖ stderr 에 이유 + rc=3";; *) bad "ⓖ stderr: $ERR";; esac
[ -z "$ERR" ] || [ "$(printf '%s\n' "$ERR" | grep -c 'REJECT 이유X')" = 3 ] && ok "ⓖ 수신자 3통 각 1줄" || bad "ⓖ stderr $(lines "$ERR")줄: $ERR"

# ── 변이 3종: 각각 해당 사례가 RED 인지 ──
mixbin() { mkdir -p "$1"; cp "$HERE/../bin/ft-hil.sh" "$HERE/../bin/ft_hil_pending.py" "$HERE/../bin/ft_latest_write.py" "$HERE/../bin/ft-harness-root.sh" "$1/" 2>/dev/null; }
fresh() {  # <폴더> — ⓐ 와 같은 4-h 세계
  world "$1" 'plz-master#9' 'plz-desk#1'; mk_h "$1/hil" h1; fin "$1/hil" h1; mk_h "$1/hil" h2; mk_h "$1/hil" h3; mk_h "$1/hil" h4
  printf 'hold %s byz-x 사유\n' "$(date +%s)" > "$1/hil/h4.held"; }

echo "== 변이 M1 _desk 수신 줄 삭제 → ⓑ RED(2통)"
mixbin "$T/mb1"; sed 's/ "\$(seat_of "\$c" _desk)"//' "$SRC" > "$T/mb1/ft-hil-notify.sh"
! cmp -s "$SRC" "$T/mb1/ft-hil-notify.sh" && ok "M1 사본 ≠ 원본" || bad "M1 사본 = 원본"
world "$T/m1" 'plz-master#9' 'plz-desk#1'; mk_h "$T/m1/hil" h1; mk_h "$T/m1/hil" h2
run "$T/mb1/ft-hil-notify.sh" "$T/m1" 'req#1'
[ "$SENT" = "req#1 plz-master#9 " ] && ok "M1 = 2통(_desk 빠짐) → ⓑ RED" || bad "M1 수신: «${SENT}»"

echo "== 변이 M2 목록 호출 삭제 → ⓐ RED(화면 0줄·꼬리 0)"
mixbin "$T/mb2"; grep -vF 'pending_block "${m%/*}"' "$SRC" > "$T/mb2/ft-hil-notify.sh"
! cmp -s "$SRC" "$T/mb2/ft-hil-notify.sh" && ok "M2 사본 ≠ 원본" || bad "M2 사본 = 원본"
fresh "$T/m2"; run "$T/mb2/ft-hil-notify.sh" "$T/m2" 'req#1'
[ -z "$OUT" ] && ok "M2 stdout 0줄 → ⓐ RED" || bad "M2 stdout: «${OUT}»"
case "$BODY" in *"남은"*) bad "M2 꼬리가 남았다: «${BODY}»";; *) ok "M2 꼬리 0 → ⓒ RED";; esac

echo "== 변이 M3 보류 필터 무시(--each --held) → ⓐ RED(h4 가 목록에)"
mixbin "$T/mb3"; sed 's/--pending --each 2>\/dev\/null/--pending --each --held 2>\/dev\/null/' "$SRC" > "$T/mb3/ft-hil-notify.sh"
! cmp -s "$SRC" "$T/mb3/ft-hil-notify.sh" && ok "M3 사본 ≠ 원본" || bad "M3 사본 = 원본"
fresh "$T/m3"; run "$T/mb3/ft-hil-notify.sh" "$T/m3" 'req#1'
first="$(printf '%s\n' "$OUT" | sed -n 1p)"
printf '%s\n' "$first" | grep -Eq '^남은 미실행 h 2: h2\([0-9]+분\) h3\([0-9]+분\)$' && bad "M3 이 ⓐ 를 못 깬다: «${OUT}»" || ok "M3 이 ⓐ 를 깬다: «${first}»"

echo "단계 초: 전체 $(( $(date +%s) - s ))"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
